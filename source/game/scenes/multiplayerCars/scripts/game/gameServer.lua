-- Game rules on top of Net.Server: one car and one on-foot walker per player, seats for up to four
-- riders, a bot,
-- collisions with replicated dents, and nitro refills granted for rewarded ads.
--
-- Clients only ask (sit / nitroAd); the server decides. A reward is never granted from a client
-- claim alone: options.verifyReward(player, token) can check it against the ad network's
-- server-side verification, and refills are rate limited either way.
local Net = require('source.engine.net')
local Plugins = require('source.engine.plugins')
local CarEntity = require('scene.scripts.game.carEntity')
local Arena = require('scene.scripts.game.arena')
local Bot = require('scene.scripts.game.bot')
local PhysicsCar = require('scene.scripts.game.physicsCar')
local WalkerEntity = require('scene.scripts.game.walkerEntity')

local GameServer = {}
GameServer.__index = GameServer

local SIT_RANGE = 10
local ABANDONED_SECONDS = 20
local DENT_COOLDOWN = 0.25
local SEATS = 4

-- options: port, maxPlayers, name, simulate (link simulation), bot (default true),
-- adCooldown (seconds between refills per player, default 20), verifyReward(player, token),
-- sightRadius, world (a World3D with physics: cars become Body3D rigid bodies stepped by it).
function GameServer.new(context, options)
    options = options or {}
    local server = Net.Server.new(context, {
        port = options.port,
        maxPlayers = options.maxPlayers or 8,
        simulate = options.simulate,
        discoveryPort = options.discoveryPort,
    })
    local self = setmetatable({
        server = server,
        options = options,
        cars = {}, -- netId -> car model
        bodies = {}, -- netId -> PhysicsCar
        walkers = {}, -- player id -> walker model
        ownCars = {}, -- player id -> netId of the car spawned for that player
        order = {}, -- netIds in spawn order (stable iteration)
        playerCars = {}, -- player id -> netId
        refills = {}, -- player id -> server time of the last refill
        nextSpawn = 1,
        bot = nil,
    }, GameServer)
    CarEntity.define(server)
    WalkerEntity.define(server)
    self:bindRemotes()
    server.playerAdded:connect(function(player)
        if options.hostsPlayer and not self.hostPlayer then
            self.hostPlayer = player -- the first client is the hosting machine's own player
        end
        self:onPlayerAdded(player)
    end)
    server.playerRemoved:connect(function(player)
        self:leaveCar(player)
        self.walkers[player.id] = nil
        self.refills[player.id] = nil
    end)
    server.ticked:connect(function(dt)
        self:onTick(dt)
    end)
    self.options.name = options.name or 'Katsa cars'
    if options.world and options.world.physics then
        local physics = options.world.physics
        self.previousBeforeStep = physics.beforeStep
        physics.beforeStep = function(world, dt)
            if self.previousBeforeStep then
                self.previousBeforeStep(world, dt)
            end
            for _, netId in ipairs(self.order) do
                local body = self.bodies[netId]
                if body then
                    body:setInput(self.cars[netId].input)
                    body:step(dt)
                end
            end
        end
    end
    return self
end

function GameServer:start()
    self.server:start()
    -- Another server on this machine may already own the discovery port; the game still runs.
    local advertised, problem = pcall(self.server.advertise, self.server, {
        name = self.options.name,
        game = 'cars',
    })
    if not advertised then
        katsa.log.write('warn', 'LAN advertisement unavailable: ' .. tostring(problem))
    end
    if self.options.bot ~= false then
        self:spawnBot()
    end
    return self
end

function GameServer:stop()
    self.server:stop()
    local physics = self.options.world and self.options.world.physics
    if physics and physics.beforeStep ~= nil then
        physics.beforeStep = self.previousBeforeStep
    end
    for netId, body in pairs(self.bodies) do
        body:destroy()
        self.bodies[netId] = nil
    end
end

function GameServer:update(dt)
    self.server:update(dt)
end

local function seatList(car)
    local list = {}
    for index = 1, SEATS do
        list[index] = car.seats[index] or 0
    end
    return list
end

function GameServer:register(model, netId)
    self.cars[netId] = model
    self.order[#self.order + 1] = netId
end

function GameServer:spawnCar(args, authority)
    local model, netId = self.server:spawn('Car', args, authority)
    self:register(model, netId)
    local world = self.options.world
    if world and world.physics then
        self.bodies[netId] = PhysicsCar.new(world, model, netId)
    end
    return model, netId
end

function GameServer:nextSpawnPoint()
    local point = Arena.spawns[(self.nextSpawn - 1) % #Arena.spawns + 1]
    self.nextSpawn = self.nextSpawn + 1
    return point
end

function GameServer:spawnBot()
    local point = Arena.spawns[#Arena.spawns]
    local model, netId =
        self:spawnCar({ x = point[1], z = point[2], heading = point[3], bot = true })
    local Pathfinding = Plugins.require('pathfinding')
    self.bot = Bot.new(model, {
        grid = Arena.buildGrid(Pathfinding.Grid),
        sightRadius = self.options.sightRadius,
    })
    self.botId = netId
    return model
end

-- Each player gets a parked car and appears on foot beside it.
function GameServer:onPlayerAdded(player)
    local point = self:nextSpawnPoint()
    local _, netId = self:spawnCar({ x = point[1], z = point[2], heading = point[3] })
    self.ownCars[player.id] = netId
    local heading = math.rad(point[3])
    local x, z = point[1] + math.cos(heading) * 3, point[2] - math.sin(heading) * 3
    local walker = self.server:spawn('Walker', {
        x = x,
        y = Arena.ground(x, z) + 0.1,
        z = z,
        heading = point[3],
        playerId = player.id,
        name = player.name,
    }, player)
    self.walkers[player.id] = walker
end

-- Gives the car's physics to its driver's client, or back to the server (nil, or the hosting
-- machine's own player, whose input the server reads directly: it shares this physics world).
function GameServer:assignDriver(netId, player)
    local car, body = self.cars[netId], self.bodies[netId]
    local remote = player ~= nil and player ~= self.hostPlayer
    self.server:setAuthority(netId, remote and player or nil)
    if body then
        body:setMode(remote and 'follow' or 'dynamic')
    end
    if not remote then
        car.input = {}
    end
end

function GameServer:publishSeats(netId)
    local car = self.cars[netId]
    local entity = self.server:findEntity(netId)
    if not (car and entity) then
        return
    end
    entity.args.seats = seatList(car)
    self.server:remote('seats'):fireAll(netId, entity.args.seats)
end

function GameServer:findPlayer(id)
    for _, player in ipairs(self.server:getPlayers()) do
        if player.id == id then
            return player
        end
    end
end

-- Removes a player from whichever car they sit in. The next rider takes the wheel.
function GameServer:leaveCar(player)
    local netId = self.playerCars[player.id]
    self.playerCars[player.id] = nil
    local car = netId and self.cars[netId]
    if not car then
        return
    end
    local seat = car:leave(player.id)
    if seat == 1 then
        for index = 2, SEATS do
            if car.seats[index] then
                car.seats[1], car.seats[index] = car.seats[index], nil
                break
            end
        end
        self:assignDriver(netId, car.seats[1] and self:findPlayer(car.seats[1]) or nil)
    end
    if car:getOccupants() == 0 then
        car.emptySince = self.server.time
    end
    self:publishSeats(netId)
end

-- Gets a player out of their car, onto the ground beside it. Returns true, x, y, z.
function GameServer:exit(player)
    local netId = self.playerCars[player.id]
    local car = netId and self.cars[netId]
    if not car then
        return false, 'not in a car'
    end
    local heading = math.rad(car.heading)
    local x, z = car.x + math.cos(heading) * 2.8, car.z - math.sin(heading) * 2.8
    self:leaveCar(player)
    return true, x, Arena.ground(x, z) + 0.2, z
end

-- Moves a player into another car. Returns the seat or nil, reason.
function GameServer:seat(player, netId)
    local target = self.cars[netId]
    local mine = self.cars[self.playerCars[player.id]]
    if not target or target.isBot then
        return nil, 'no such car'
    end
    if mine == target then
        return nil, 'already there'
    end
    -- Distance is measured from the car the player rides, or from the walker on foot.
    local origin = mine or self.walkers[player.id]
    if origin and (origin.x - target.x) ^ 2 + (origin.z - target.z) ^ 2 > SIT_RANGE ^ 2 then
        return nil, 'too far'
    end
    if target:getOccupants() >= SEATS then
        return nil, 'full'
    end
    self:leaveCar(player)
    local seat = target:sit(player.id)
    self.playerCars[player.id] = netId
    target.emptySince = nil
    if seat == 1 then
        self:assignDriver(netId, player)
    end
    self:publishSeats(netId)
    return seat
end

function GameServer:bindRemotes()
    local server = self.server
    server:remote('sit'):onRequest(function(player, netId)
        return self:seat(player, netId)
    end)
    server:remote('exit'):onRequest(function(player)
        return self:exit(player)
    end)
    -- A driver's client simulates its own car, so it reports the collisions it felt.
    server:remote('impact'):onServer(function(player, netId, x, z, nx, nz, speed)
        local car = self.cars[netId]
        if car and self.server:getAuthority(netId) == player and #car.impacts < 8 then
            car.impacts[#car.impacts + 1] =
                { x = x, z = z, nx = nx, nz = nz, speed = math.min(speed, 40) }
        end
    end)
    server:remote('nitroAd'):onRequest(function(player, token)
        return self:grantNitro(player, token)
    end)
end

-- A rewarded ad finished on a client; refill that player's car. Returns ok, reason.
function GameServer:grantNitro(player, token)
    local netId = self.playerCars[player.id]
    local car = netId and self.cars[netId]
    if not car then
        return false, 'no car'
    end
    local now = self.server.time
    local cooldown = self.options.adCooldown or 20
    local last = self.refills[player.id]
    if last and now - last < cooldown then
        return false, 'cooldown'
    end
    local verify = self.options.verifyReward
    if verify and not verify(player, token) then
        return false, 'unverified'
    end
    self.refills[player.id] = now
    car.nitro = 1
    if self.server:getAuthority(netId) == player then
        self.server:remote('refill'):fireClient(player, netId)
    end
    return true
end

function GameServer:addDent(netId, car, impact, now)
    if car.lastDent and now - car.lastDent < DENT_COOLDOWN then
        return
    end
    if car.dents:addImpact(impact) then
        car.lastDent = now
        local list = car.dents:serialize()
        local entity = self.server:findEntity(netId)
        if entity then
            entity.args.dents = list
        end
        self.server:remote('dents'):fireAll(netId, list)
    end
end

-- Sends the bot's current route (flat x, z pairs plus its goal) a few times a second so clients
-- can draw it for debugging.
function GameServer:broadcastBotPath(now)
    local bot = self.bot
    if not bot or (self.lastPathSend or -1) + 0.4 > now then
        return
    end
    self.lastPathSend = now
    local flat = {}
    local path = bot.path
    if path then
        -- Packets are small; the nearest points are the useful ones.
        for index = path.index, math.min(#path.points, path.index + 39) do
            local point = path.points[index]
            flat[#flat + 1], flat[#flat + 2] = point[1], point[2]
        end
    end
    local car = self.cars[self.botId]
    self.server:remote('botPath'):fireAll(
        bot.mode or 'patrol',
        car and car.x or 0,
        car and car.z or 0,
        flat
    )
end

function GameServer:onTick(dt)
    local now = self.server.time
    local models = {}
    for _, netId in ipairs(self.order) do
        models[#models + 1] = self.cars[netId]
    end
    for _, netId in ipairs(self.order) do
        local car = self.cars[netId]
        if car then
            if netId == self.botId and self.bot then
                car.input = self.bot:think(models, dt)
            elseif not car:getDriver() then
                car.input = {} -- coast to a stop
            elseif self.hostPlayer and car:getDriver() == self.hostPlayer.id then
                -- The hosting player shares this physics world: drive from its input directly.
                car.input = self.hostPlayer.lastInput or {}
            end
        end
    end
    self:broadcastBotPath(now)
    local removed
    for _, netId in ipairs(self.order) do
        local car = self.cars[netId]
        local body = self.bodies[netId]
        if body then
            body:readState()
            if body:needsReset(dt) then
                local point = CarEntity.spawnPoint(netId)
                body:respawn(point[1], point[2], point[3])
            end
            for _, impact in ipairs(body.impacts) do
                car.impacts[#car.impacts + 1] = impact
            end
            body.impacts = {}
        end
        for _, impact in ipairs(car.impacts) do
            self:addDent(netId, car, impact, now)
        end
        car.impacts = {}
        if car.emptySince and not car.isBot and now - car.emptySince > ABANDONED_SECONDS then
            removed = removed or {}
            removed[#removed + 1] = netId
        end
    end
    for _, netId in ipairs(removed or {}) do
        self:removeCar(netId)
    end
end

function GameServer:removeCar(netId)
    if self.bodies[netId] then
        self.bodies[netId]:destroy()
        self.bodies[netId] = nil
    end
    self.cars[netId] = nil
    for index, id in ipairs(self.order) do
        if id == netId then
            table.remove(self.order, index)
            break
        end
    end
    self.server:despawn(netId)
end

return GameServer
