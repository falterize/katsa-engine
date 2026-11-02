-- Client side of the car game: connection, replicated cars, seats, dents and the nitro ad flow.
local Net = require('source.engine.net')
local Plugins = require('source.engine.plugins')
local CarEntity = require('scene.scripts.game.carEntity')
local PhysicsCar = require('scene.scripts.game.physicsCar')
local WalkerEntity = require('scene.scripts.game.walkerEntity')

local GameClient = {}
GameClient.__index = GameClient

-- options: address, port, name, simulate, input = function() -> { throttle, steer, nitro },
-- world (a World3D with physics: the client then simulates the cars it owns and keeps
-- kinematic stand-ins for the others; leave nil when a server in this process owns the bodies).
function GameClient.new(context, options)
    local client = Net.Client.new(context, {
        address = options.address,
        port = options.port,
        name = options.name,
        simulate = options.simulate,
    })
    local self = setmetatable({
        client = client,
        options = options,
        cars = {}, -- netId -> car model
        walkers = {}, -- netId -> walker model (every player on foot)
        bodies = {}, -- netId -> PhysicsCar (owned dynamic, others follow)
        input = options.input or function()
            return {}
        end,
        onCarAdded = nil,
        onCarRemoved = nil,
        onDents = nil,
    }, GameClient)
    CarEntity.define(client)
    WalkerEntity.define(client)
    client.inputProvider = function()
        return self.input()
    end
    client.entitySpawned:connect(function(object, kind, netId, owned)
        if kind == 'Walker' then
            self.walkers[netId] = object
            if owned then
                self.ownWalker, self.ownWalkerId = object, netId
            end
            if self.onWalkerAdded then
                self.onWalkerAdded(netId, object, owned)
            end
        elseif kind == 'Car' then
            self.cars[netId] = object
            self:attachBody(netId, object, owned)
            if self.onCarAdded then
                self.onCarAdded(netId, object)
            end
        end
    end)
    client.entityRemoved:connect(function(_, kind, netId)
        if kind == 'Walker' then
            self.walkers[netId] = nil
            if self.onWalkerRemoved then
                self.onWalkerRemoved(netId)
            end
        elseif kind == 'Car' then
            self.cars[netId] = nil
            if self.bodies[netId] then
                self.bodies[netId]:destroy()
                self.bodies[netId] = nil
            end
            if self.onCarRemoved then
                self.onCarRemoved(netId)
            end
        end
    end)
    client.authorityChanged:connect(function(object, _, owned)
        for netId, car in pairs(self.cars) do
            if car == object and self.bodies[netId] then
                self.bodies[netId]:setMode(owned and 'dynamic' or 'follow')
            end
        end
    end)
    -- Chat and roster: lines are kept for the UI (`onChat`) and echoed to the console.
    self.chatLog, self.hostId = {}, 0
    client:remote('chat'):onClient(function(id, name, isHost, text)
        local line = { id = id, name = name, host = isHost, text = text }
        self.chatLog[#self.chatLog + 1] = line
        if #self.chatLog > 100 then
            table.remove(self.chatLog, 1)
        end
        katsa.log.log(('[chat] %s%s: %s'):format(isHost and '[HOST] ' or '', name, text), 'multiplayerCars')
        if self.onChat then
            self.onChat(line)
        end
    end)
    client:remote('host'):onClient(function(id)
        self.hostId = id
        if self.onRoster then
            self.onRoster()
        end
    end)
    client.playerJoined:connect(function(player)
        katsa.log.log(('[client] %s joined'):format(player.name), 'multiplayerCars')
        if self.onRoster then
            self.onRoster()
        end
    end)
    client.playerLeft:connect(function(player)
        katsa.log.log(('[client] %s left'):format(player.name), 'multiplayerCars')
        if self.onRoster then
            self.onRoster()
        end
    end)
    client:remote('refill'):onClient(function(netId)
        local car = self.cars[netId]
        if car then
            car.nitro = 1 -- the server granted a refill to a car this client simulates
        end
    end)
    client:remote('seats'):onClient(function(netId, list)
        local car = self.cars[netId]
        if car then
            car.seats = {}
            for index, id in ipairs(list) do
                if id ~= 0 then
                    car.seats[index] = id
                end
            end
        end
    end)
    client:remote('botPath'):onClient(function(mode, x, z, flat, y)
        self.botRoute = { mode = mode, x = x, y = y, z = z, points = flat }
    end)
    client:remote('dents'):onClient(function(netId, list, detached)
        local car = self.cars[netId]
        if car then
            car.dents:load(list)
            local before = car.detached or 0
            car.detached = detached or before
            car.damage.detached = car.detached
            for index = 1, 4 do
                local mask = 2 ^ (index - 1)
                if math.floor(car.detached / mask) % 2 == 1 and math.floor(before / mask) % 2 == 0 then
                    if self.onWheelLost then
                        self.onWheelLost(netId, car, index)
                    end
                end
            end
            if self.onDents then
                self.onDents(netId, car)
            end
        end
    end)
    return self
end

function GameClient:attachBody(netId, model, owned)
    local world = self.options.world
    if not (world and world.physics) then
        return
    end
    self.bodies[netId] =
        PhysicsCar.new(world, model, netId, { mode = owned and 'dynamic' or 'follow' })
    if not self.hooked then
        self.hooked = true
        local physics = world.physics
        self.previousBeforeStep = physics.beforeStep
        physics.beforeStep = function(self_, dt)
            if self.previousBeforeStep then
                self.previousBeforeStep(self_, dt)
            end
            for _, body in pairs(self.bodies) do
                if body.mode == 'dynamic' then
                    body:setInput(self.input())
                end
                body:step(dt)
            end
        end
    end
end

-- True when this client runs physics for cars (it needs the world stepped every frame).
function GameClient:simulates()
    return self.options.world ~= nil and self.options.world.physics ~= nil
end

-- After the physics step: read the cars this client owns and report what they hit.
function GameClient:afterPhysics()
    for netId, body in pairs(self.bodies) do
        if body.mode == 'dynamic' then
            body:readState()
            if body:needsReset(1 / 60) then
                local point = CarEntity.spawnPoint(netId)
                body:respawn(point[1], point[2], point[3])
            end
            for _, impact in ipairs(body.impacts) do
                self.client:remote('impact'):fireServer(
                    netId,
                    impact.x,
                    impact.z,
                    impact.nx,
                    impact.nz,
                    impact.speed,
                    impact.y,
                    impact.ny
                )
            end
            body.impacts = {}
        end
    end
end

function GameClient:connect()
    self.client:connect()
    return self
end

function GameClient:update(dt)
    self.client:update(dt)
    if Plugins.has('ads') then
        Plugins.require('ads').update(dt)
    end
end

function GameClient:disconnect()
    local world = self.options.world
    if self.hooked and world and world.physics then
        world.physics.beforeStep = self.previousBeforeStep
    end
    for netId, body in pairs(self.bodies) do
        body:destroy()
        self.bodies[netId] = nil
    end
    self.client:disconnect()
end

function GameClient:isConnected()
    return self.client:isConnected()
end

function GameClient:getPing()
    return self.client:getPing()
end

function GameClient:getPlayerId()
    return self.client.playerId
end

-- NetId of the car this player rides in, with the model, or nil.
function GameClient:getCar()
    local id = self.client.playerId
    for netId, car in pairs(self.cars) do
        for index = 1, car.config.seats do
            if car.seats[index] == id then
                return netId, car, index
            end
        end
    end
end

-- The nearest car with a free seat within `range` of the player: measured from the car they
-- ride, or from their walker on foot. The car they already sit in is not a candidate.
function GameClient:findNearbyCar(range)
    local _, mine = self:getCar()
    local origin = mine or self.ownWalker
    if not origin then
        return nil
    end
    local best, bestDistance
    for netId, car in pairs(self.cars) do
        if car ~= mine and not car.isBot and car:getOccupants() < car.config.seats then
            local distance = math.sqrt((car.x - origin.x) ^ 2 + (car.z - origin.z) ^ 2)
            if distance <= range and (not bestDistance or distance < bestDistance) then
                best, bestDistance = netId, distance
            end
        end
    end
    return best
end

-- Sends a chat line to everyone (the server trims and rate-limits it).
function GameClient:sendChat(text)
    self.client:remote('chat'):fireServer(text)
end

-- Host only: disconnects a player. callback(ok, reason).
function GameClient:kickPlayer(id, callback, reason)
    self.client:remote('kick'):request(callback or function() end, id, reason or '')
end

-- Players currently in the game: array of { id, name }.
function GameClient:getPlayers()
    local list = {}
    for _, player in pairs(self.client.players) do
        list[#list + 1] = { id = player.id, name = player.name }
    end
    return list
end

-- Asks to leave the current car; callback(ok, x, y, z) gets the spot on the ground.
function GameClient:exitCar(callback)
    self.client:remote('exit'):request(callback or function() end)
end

function GameClient:sit(netId, callback)
    self.client:remote('sit'):request(callback or function() end, netId)
end

-- Shows a rewarded ad, then asks the server for the refill. callback(ok, reason).
function GameClient:requestNitroRefill(callback)
    callback = callback or function() end
    local function ask(token)
        self.client:remote('nitroAd'):request(function(ok, reason)
            callback(ok == true, reason)
        end, token)
    end
    if not Plugins.has('ads') then
        return callback(false, 'ads unavailable')
    end
    local Ads = Plugins.require('ads')
    Ads.showRewarded(function(result)
        if result.rewarded then
            ask(result.token or '')
        else
            callback(false, result.error or 'ad skipped')
        end
    end)
end

return GameClient
