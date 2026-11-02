-- Scene controller: menu, hosting/joining, the per-frame input, cars on screen and the camera.
local Net = require('source.engine.net')
local Plugins = require('source.engine.plugins')
local ArenaView = require('scene.scripts.view.arenaView')
local CarView = require('scene.scripts.view.carView')
local GameServer = require('scene.scripts.game.gameServer')
local GameClient = require('scene.scripts.game.gameClient')
local AdsConfig = require('scene.scripts.game.adsConfig')
local Interface = require('scene.scripts.ui.interface')
local Menu = Interface.Menu
local Hud = Interface.Hud

local Session = {}
-- Exposed so tests can build a second, independent client and physics world.
Session.GameClient, Session.ArenaView = GameClient, ArenaView
Session.__index = Session

local DEFAULT_PORT = 7777
local SIT_RANGE = 10

local function pressedOnce(self, name, down)
    local was = self.held[name]
    self.held[name] = down
    return down and not was
end

function Session.new(scene)
    local self =
        setmetatable({ scene = scene, views = {}, held = {}, mode = 'menu', lanTimer = 0 }, Session)
    -- Meters, real gravity: the terrain and walls are static bodies the vehicles will drive on.
    scene:createPhysics({ unitsPerMeter = 1, gravity = { 0, -9.81, 0 }, backend = 'jolt' })
    ArenaView.build(scene)
    self.menu = Menu.create(scene, {
        host = function(name)
            self:host(name, DEFAULT_PORT)
        end,
        join = function(address, port, name)
            self:join(address, port, name)
        end,
    })
    self.hud = Hud.create(scene, {
        sit = function()
            self:changeCar()
        end,
        ad = function()
            self:watchAd()
        end,
        leave = function()
            self:leave()
        end,
        pathDebug = function()
            self.pathDebug = not self.pathDebug
            self.hud:setPathDebug(self.pathDebug)
            if not self.pathDebug then
                self:hidePathMarkers()
            end
        end,
    })
    self.hud:setVisible(false)
    local ok, browser = pcall(Net.browse)
    self.browser = ok and browser or nil
    if Plugins.has('ads') then
        local Ads = Plugins.require('ads')
        Ads.configure(AdsConfig.resolve())
        Ads.load()
    end
    -- A camera of our own so no free-fly controller fights the chase logic.
    self.camera = scene.world:create('Camera3D', {
        name = 'ChaseCamera',
        position = { 0, 45, -75 },
        rotation = { -30, 0, 0 },
        drawDistance = 400,
    })
    scene.camera = scene.world:setCamera(self.camera)
    -- Dragging (mouse or touch) orbits the chase camera around the car.
    self.orbit = { yaw = 0, pitch = 0 }
    scene.input.actions:on('Look', function(_, look)
        self.orbit.yaw = self.orbit.yaw - look[1] * 0.4
        self.orbit.pitch = math.max(-20, math.min(55, self.orbit.pitch + look[2] * 0.3))
        self.orbitIdle = 0
    end)
    self:applyLaunchArguments()
    return self
end

-- Debug markers for the bot's route: small spheres on the terrain, plus one on the bot.
function Session:hidePathMarkers()
    for _, marker in ipairs(self.pathMarkers or {}) do
        marker.visible = false
    end
end

function Session:updatePathMarkers()
    local route = self.client and self.client.botRoute
    if not route then
        return
    end
    local Arena = require('scene.scripts.game.arena')
    self.pathMarkers = self.pathMarkers or {}
    local count = #route.points / 2 + 1
    for index = 1, math.max(count, #self.pathMarkers) do
        local marker = self.pathMarkers[index]
        if index <= count and not marker then
            marker = self.scene.world:create('Mesh3D', {
                name = 'PathMarker' .. index,
                kind = 'sphere',
                size = { 0.7, 0.7, 0.7 },
                color = { 1, 0.9, 0.2 },
                unlit = true,
                castShadow = false,
            })
            self.pathMarkers[index] = marker
        end
        if marker then
            marker.visible = index <= count
            if index <= count then
                local x, z = route.points[index * 2 - 1], route.points[index * 2]
                if index == count then
                    x, z = route.x, route.z
                    marker.color = route.mode == 'chase' and { 1, 0.2, 0.2 } or { 0.2, 1, 0.4 }
                end
                marker.position = { x, Arena.ground(x, z) + 0.9, z }
            end
        end
    end
end

-- --host [port], --connect address[:port], --name Name
function Session:applyLaunchArguments()
    local args = katsa.launchArguments or {}
    local name, hostPort, target = 'Player', nil, nil
    for index, argument in ipairs(args) do
        if argument == '--name' then
            name = args[index + 1] or name
        elseif argument == '--host' then
            hostPort = tonumber(args[index + 1]) or DEFAULT_PORT
        elseif argument == '--connect' then
            target = args[index + 1]
        end
    end
    if hostPort then
        self:host(name, hostPort)
    elseif target then
        local address, port = target:match('^([^:]+):?(%d*)$')
        if address then
            self:join(address, tonumber(port) or DEFAULT_PORT, name)
        end
    end
end

function Session:input()
    local keys = self.scene.input.actions.keys
    local throttle = (keys.w or keys.up) and 1 or 0
    if keys.s or keys.down then
        throttle = throttle - 1
    end
    local steer = 0
    if keys.d or keys.right then
        steer = steer + 1
    end
    if keys.a or keys.left then
        steer = steer - 1
    end
    return { throttle = throttle, steer = steer, nitro = keys.lshift == true or keys.rshift == true }
end

function Session:startClient(address, port, name)
    local client = GameClient.new({}, {
        address = address,
        port = port,
        name = (name and name ~= '') and name or 'Player',
        world = (not self.server) and self.scene.world or nil,
        input = function()
            return self:input()
        end,
    })
    client.onCarAdded = function(netId, model)
        self.views[netId] = CarView.new(self.scene, netId, model)
    end
    client.onCarRemoved = function(netId)
        if self.views[netId] then
            self.views[netId]:destroy()
            self.views[netId] = nil
        end
    end
    client.onDents = function(netId)
        if self.views[netId] then
            self.views[netId]:markDirty()
        end
    end
    client.client.disconnected:connect(function(reason)
        if self.mode == 'playing' then
            self:leave(reason and ('Disconnected: ' .. tostring(reason)) or 'Disconnected')
        end
    end)
    self.client = client
    self.mode = 'connecting'
    self.targetAddress, self.targetPort = address, port
    self.connectTime = 0
    self.menu:setStatus(('Connecting to %s:%d ...'):format(address, port))
    client:connect()
end

function Session:host(name, port)
    local ok, problem = pcall(function()
        self.server = GameServer.new({}, {
            port = port,
            name = (name or 'Player') .. "'s game",
            world = self.scene.world,
            hostsPlayer = true,
        })
        self.server:start()
    end)
    if not ok then
        self.server = nil
        self.menu:setStatus('Could not host: ' .. tostring(problem))
        return
    end
    self:startClient('127.0.0.1', port, name)
end

function Session:join(address, port, name)
    self:startClient(address, port, name)
end

function Session:leave(message)
    if self.client then
        self.client:disconnect()
        self.client = nil
    end
    if self.server then
        self.server:stop()
        self.server = nil
    end
    for netId, view in pairs(self.views) do
        view:destroy()
        self.views[netId] = nil
    end
    self.mode = 'menu'
    self.menu:setVisible(true)
    self.hud:setVisible(false)
    self.menu:setStatus(message or '')
end

function Session:changeCar()
    local client = self.client
    if not client then
        return
    end
    local target = client:findNearbyCar(SIT_RANGE)
    if not target then
        self.hud:flash('No car with a free seat nearby')
        return
    end
    client:sit(target, function(seat, reason)
        self.hud:flash(seat and ('Seat ' .. seat) or ('Cannot sit: ' .. tostring(reason)))
    end)
end

function Session:watchAd()
    if not self.client then
        return
    end
    self.hud:flash('Loading ad...')
    self.client:requestNitroRefill(function(ok, reason)
        self.hud:flash(ok and 'Nitro refilled!' or ('No refill: ' .. tostring(reason)))
    end)
end

function Session:updateCamera(dt, car)
    local camera = self.camera
    -- The orbit offset eases back behind the car when the player stops dragging.
    local orbit = self.orbit
    self.orbitIdle = (self.orbitIdle or 0) + dt
    if self.orbitIdle > 3 then
        local ease = math.min(1, dt * 2)
        orbit.yaw, orbit.pitch = orbit.yaw * (1 - ease), orbit.pitch * (1 - ease)
    end
    local heading = math.rad(car.heading + orbit.yaw)
    local fx, fz = math.sin(heading), math.cos(heading)
    local rise = 5 + orbit.pitch * 0.25
    local target = { car.x - fx * 11, car.y + rise, car.z - fz * 11 }
    local p = camera.position
    local k = math.min(1, dt * 6)
    local x = p[1] + (target[1] - p[1]) * k
    local y = p[2] + (target[2] - p[2]) * k
    local z = p[3] + (target[3] - p[3]) * k
    -- Keep the camera between 8 and 15 units behind however hard the car accelerates.
    local ox, oz = x - car.x, z - car.z
    local distance = math.sqrt(ox * ox + oz * oz)
    local clamped = math.max(8, math.min(15, distance))
    if distance > 1e-6 and clamped ~= distance then
        x, z = car.x + ox / distance * clamped, car.z + oz / distance * clamped
    end
    camera.position = { x, y, z }
    p = camera.position
    local dx, dy, dz = car.x - p[1], car.y + 1.5 - p[2], car.z - p[3]
    local yaw = math.deg(math.atan2(dx, dz))
    local pitch = math.deg(math.atan2(dy, math.sqrt(dx * dx + dz * dz)))
    camera.rotation = { pitch, yaw, 0 }
end

function Session:update(dt)
    local keys = self.scene.input.actions.keys
    if self.server then
        -- The hosted cars are rigid bodies: step the world, then let the server read them.
        self.scene.physics:update(dt)
        self.server:update(dt)
    elseif self.client and self.client:simulates() then
        -- A joined player simulates the car it drives and keeps stand-ins for the others.
        self.scene.physics:update(dt)
        self.client:afterPhysics()
    end
    if self.client then
        self.client:update(dt)
    end
    if self.mode == 'menu' then
        self.lanTimer = self.lanTimer - dt
        if self.browser then
            if self.lanTimer <= 0 then
                self.browser.refresh()
                self.browser.refresh('127.0.0.1')
                self.lanTimer = 1.5
            end
            self.menu:setServers(self.browser.update())
        end
        return
    end
    if self.mode == 'connecting' then
        self.connectTime = self.connectTime + dt
        if self.client:isConnected() then
            self.mode = 'playing'
            self.menu:setVisible(false)
            self.hud:setVisible(true)
        elseif self.client.client.rejection or self.connectTime > 6 then
            local peer = self.client.client.host and self.client.client.host.server
            local reason = self.client.client.rejection
            if not reason then
                reason = ('No answer from %s:%s (connection %s). Check that the host is still running, the address and port are right, and that the firewall allows UDP %s.'):format(
                    tostring(self.targetAddress),
                    tostring(self.targetPort),
                    peer and peer:getState() or 'unknown',
                    tostring(self.targetPort)
                )
            end
            print('[multiplayerCars] ' .. reason)
            self:leave(reason)
        end
        return
    end
    if pressedOnce(self, 'e', keys.e == true) then
        self:changeCar()
    end
    if pressedOnce(self, 'n', keys.n == true) then
        self:watchAd()
    end
    local _, car, seat = self.client:getCar()
    for _, view in pairs(self.views) do
        view:update(dt)
    end
    if self.pathDebug then
        self:updatePathMarkers()
    end
    if car then
        self:updateCamera(dt, car)
        local players = 0
        for _ in pairs(self.client.client.players) do
            players = players + 1
        end
        self.hud:update(dt, {
            speed = car.speed,
            nitro = car.nitro,
            info = ('%s  -  seat %d/%d  -  %d players  -  ping %d ms'):format(
                seat == 1 and 'Driving' or 'Passenger',
                seat,
                car.config.seats,
                players,
                math.floor(self.client:getPing())
            ),
        })
    end
end

function Session:release()
    self:leave()
    if self.browser then
        self.browser.close()
        self.browser = nil
    end
end

return Session
