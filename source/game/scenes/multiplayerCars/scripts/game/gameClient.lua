-- Client side of the car game: connection, replicated cars, seats, dents and the nitro ad flow.
local Net = require('source.engine.net')
local Plugins = require('source.engine.plugins')
local CarEntity = require('scene.scripts.game.carEntity')
local PhysicsCar = require('scene.scripts.game.physicsCar')

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
        bodies = {}, -- netId -> PhysicsCar (owned dynamic, others follow)
        input = options.input or function()
            return {}
        end,
        onCarAdded = nil,
        onCarRemoved = nil,
        onDents = nil,
    }, GameClient)
    CarEntity.define(client)
    client.inputProvider = function()
        return self.input()
    end
    client.entitySpawned:connect(function(object, kind, netId, owned)
        if kind == 'Car' then
            self.cars[netId] = object
            self:attachBody(netId, object, owned)
            if self.onCarAdded then
                self.onCarAdded(netId, object)
            end
        end
    end)
    client.entityRemoved:connect(function(_, kind, netId)
        if kind == 'Car' then
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
    client:remote('botPath'):onClient(function(mode, x, z, flat)
        self.botRoute = { mode = mode, x = x, z = z, points = flat }
    end)
    client:remote('dents'):onClient(function(netId, list)
        local car = self.cars[netId]
        if car then
            car.dents:load(list)
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
                    impact.speed
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

-- The nearest car with a free seat within `range` of the player's own car.
function GameClient:findNearbyCar(range)
    local _, mine = self:getCar()
    if not mine then
        return nil
    end
    local best, bestDistance
    for netId, car in pairs(self.cars) do
        if car ~= mine and not car.isBot and car:getOccupants() < car.config.seats then
            local distance = math.sqrt((car.x - mine.x) ^ 2 + (car.z - mine.z) ^ 2)
            if distance <= range and (not bestDistance or distance < bestDistance) then
                best, bestDistance = netId, distance
            end
        end
    end
    return best
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
