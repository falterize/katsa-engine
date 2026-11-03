-- Scene controller: menu, hosting/joining, the per-frame input, cars on screen and the camera.
local Net = require('source.engine.net')
local Plugins = require('source.engine.plugins')
local ArenaView = require('./view.arenaView')
local CarView = require('./view.carView')
local RenderPose = require('./game.renderPose')
local Orbit = require('./cameras.orbit')
local Input = require('./controller.input')
local Pinch = require('./controller.pinch')
local Walker = require('./walker.controller')
local WalkerView = require('./walker.view')
local GameServer = require('./game.gameServer')
local GameClient = require('./game.gameClient')
local AdsConfig = require('./game.adsConfig')
local Interface = require('./ui.interface')
local Menu = Interface.Menu
local Hud = Interface.Hud
local Social = require('./ui.controller')
local Voice = require('./game.voice')

local Session = {}
-- Exposed so tests can build a second, independent client and physics world.
Session.GameClient, Session.ArenaView = GameClient, ArenaView
Session.__index = Session

local DEFAULT_PORT = 7777
local SIT_RANGE = 6

local function pressedOnce(self, name, down)
    local was = self.held[name]
    self.held[name] = down
    return down and not was
end

-- Runs `build`; a step slower than 50 ms is written to the log (and shows under the profiler's
-- 'Cars: ...' scopes), so a hitch on first use can be traced from an exported log.
local function timed(name, build, ...)
    local started = katsa.timer.getTime()
    local result = build(...)
    local ms = (katsa.timer.getTime() - started) * 1000
    if ms > 50 then
        katsa.log.write('warn', ('multiplayerCars: %s took %.0f ms'):format(name, ms))
    end
    return result
end

function Session.new(scene)
    local self =
        setmetatable({
            scene = scene,
            views = {},
            walkerViews = {},
            held = {},
            mode = 'menu',
            lanTimer = 0,
        }, Session)
    local profiler = scene.manager.profiler
    -- Meters, real gravity: the terrain and walls are static bodies the vehicles will drive on.
    scene:createPhysics({
        unitsPerMeter = 1,
        gravity = { 0, -9.81, 0 },
        backend = 'jolt',
        fixedDelta = 1 / 60,
        interpolate = true,
    })
    profiler:markLoad('Cars: physics world (Jolt)')
    ArenaView.build(scene)
    profiler:markLoad('Cars: arena meshes and colliders')
    -- The on-foot player steps with the physics world; the car server and client chain after it.
    scene.physics.beforeStep = function(_, dt)
        if self.walker then
            self.walker:step(dt)
        end
    end
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
        jump = function()
            self.jumpHeld = 0.25
        end,
        -- Toggles for phones: no need to keep a finger on the button.
        run = function()
            local input = self.scene.input
            input.runToggled = not input.runToggled
            self.hud:setToggles(input.runToggled, input.crouchToggled)
        end,
        crouch = function()
            local input = self.scene.input
            input.crouchToggled = not input.crouchToggled
            self.hud:setToggles(input.runToggled, input.crouchToggled)
        end,
        menu = function()
            self.scene.input:toggleMenu()
        end,
        chat = function()
            self.scene.input:openChat()
        end,
        zoom = function(amount)
            self.orbit:zoom(amount)
        end,
        leave = function()
            self:leave()
        end,
    })
    profiler:markLoad('Cars: menu and HUD')
    self.hud:setVisible(false)
    self.social = Social.create(scene, {
        send = function(text)
            if self.client then
                self.client:sendChat(text)
            end
        end,
        hostCommand = function(command)
            if self.client then
                self.client:hostCommand(command, function(ok, why)
                    self.hud:flash(ok and 'Done' or ('Cannot: ' .. tostring(why)))
                end)
            end
        end,
        kick = function(id)
            if self.client then
                self.client:kickPlayer(id, function(ok, why)
                    self.hud:flash(ok and 'Player kicked' or ('Cannot kick: ' .. tostring(why)))
                end)
            end
        end,
    })
    self.social.root.visible = false
    self.social.onTypingDone = function()
        self.scene.input:chatClosed()
    end
    profiler:markLoad('Cars: chat and player list')
    -- The first import of the character decodes the GLB and writes its cache (nearly a second on a
    -- first run); doing it while the scene loads keeps Host / Join from freezing.
    require('source.engine.import.models').load('scene://models/character.glb', scene.resources)
    profiler:markLoad('Cars: character model warm-up')
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
    -- The StareShooter orbit camera: dragging (mouse or touch) orbits, the wheel zooms.
    self.orbit = Orbit.new(scene, self.camera)
    scene.input = Input.new(scene, self)
    self:applyLaunchArguments()
    return self
end

-- Debug markers for the bot's route: small spheres on the terrain, plus one on the bot.
-- The bot's route (replicated by the server) goes to the pathfinding plugin's debug view, so it is
-- drawn with the NavMap and follows the one switch Environment.debug.pathfinding.
function Session:updateBotRoute()
    local route = self.client and self.client.botRoute
    if route == self.fedRoute then
        return
    end
    self.fedRoute = route
    local points = {}
    for index = 1, #route.points - 2, 3 do
        points[#points + 1] = { route.points[index], route.points[index + 1], route.points[index + 2] }
    end
    require('source.plugins.pathfinding').Debug.setRoute(self.scene.world, 'bot', {
        points = points,
        goal = { route.x, (route.y or 0) - 1.5, route.z },
        goalColor = route.mode == 'chase' and { 1, 0.2, 0.2 } or { 0.2, 1, 0.4 },
    })
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

-- Keys and the on-screen joystick (the engine's `Move` action: x = right, z = forward) both
-- steer; whichever is pushed harder wins, so the two never add up beyond full deflection.
-- Throttle/steer or forward/right from the keys and the on-screen joystick (zero in a menu).
function Session:moveAxes()
    return self.scene.input:axes()
end

function Session:input()
    local keys = self.scene.input.actions.keys
    local throttle, steer = self:moveAxes()
    return { throttle = throttle, steer = steer, nitro = keys.lshift == true or keys.rshift == true }
end

-- Hosting adds the walker and the first cars in one frame; building every view in that frame is a
-- visible hitch (the character alone is ~35 ms). Views are built one per frame instead, walker
-- first, so the new entities appear a frame or two later.
function Session:queueView(kind, netId, model)
    local queue = self.viewQueue or {}
    self.viewQueue = queue
    local entry = { kind = kind, netId = netId, model = model }
    if kind == 'walker' then
        table.insert(queue, 1, entry)
    else
        queue[#queue + 1] = entry
    end
end

function Session:unqueueView(kind, netId)
    local queue = self.viewQueue
    for i = #(queue or {}), 1, -1 do
        if queue[i].kind == kind and queue[i].netId == netId then
            table.remove(queue, i)
        end
    end
end

function Session:buildQueuedView()
    local queue = self.viewQueue
    local entry = queue and table.remove(queue, 1)
    if not entry then
        return
    end
    if entry.kind == 'car' then
        self.views[entry.netId] =
            timed('car view', CarView.new, self.scene, entry.netId, entry.model)
    else
        self.walkerViews[entry.netId] =
            timed('character view', WalkerView.new, self.scene, entry.netId, entry.model)
    end
end

function Session:startClient(address, port, name)
    local client = GameClient.new({}, {
        address = address,
        port = port,
        name = (name and name ~= '') and name or 'Player',
        world = (not self.server) and self.scene.world or nil,
        localServer = self.server and self.server.server or nil,
        input = function()
            return self:input()
        end,
    })
    self.scene.netStats = function()
        return self.client == client and client.client:getStats() or nil
    end
    client.onCarAdded = function(netId, model)
        self:queueView('car', netId, model)
    end
    client.onCarRemoved = function(netId)
        self:unqueueView('car', netId)
        if self.views[netId] then
            self.views[netId]:destroy()
            self.views[netId] = nil
        end
    end
    client.onWalkerAdded = function(netId, model, owned)
        self:queueView('walker', netId, model)
        if owned then
            self.walker = Walker.new(self.scene.world, model)
        end
    end
    client.onWalkerRemoved = function(netId)
        self:unqueueView('walker', netId)
        if self.walkerViews[netId] then
            self.walkerViews[netId]:destroy()
            self.walkerViews[netId] = nil
        end
    end
    client.onChat = function(line)
        self.social:addChat(line)
    end
    client.onRoster = function()
        self:refreshPlayers()
    end
    client.onWheelLost = function(netId, _, index)
        if self.views[netId] then
            self.views[netId]:shedWheel(index)
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
    self.voice = Voice.new(client, {
        listenerAt = function()
            local position = self.camera.position
            return position[1], position[2], position[3]
        end,
        positionOf = function(id)
            for _, walker in pairs(client.walkers) do
                if walker.playerId == id then
                    return walker.x, walker.y + 1.5, walker.z
                end
            end
        end,
    })
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
            profiler = self.scene.manager.profiler,
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
    if self.voice then
        self.voice:destroy()
        self.voice = nil
    end
    if self.client then
        self.client:disconnect()
        self.client = nil
    end
    if self.server then
        self.server:stop()
        self.server = nil
    end
    self.viewQueue = nil
    for netId, view in pairs(self.views) do
        view:destroy()
        self.views[netId] = nil
    end
    for netId, view in pairs(self.walkerViews) do
        view:destroy()
        self.walkerViews[netId] = nil
    end
    if self.walker then
        self.walker:destroy()
        self.walker = nil
    end
    self.mode = 'menu'
    self.menu:setVisible(true)
    self.hud:setVisible(false)
    self.social.root.visible = false
    self.menu:setStatus(message or '')
end

-- E: leave the car you ride, or get into the nearest car with a free seat.
function Session:changeCar()
    local client = self.client
    if not client then
        return
    end
    if client:getCar() then
        client:exitCar(function(ok, x, y, z)
            if ok and self.walker then
                self.walker:place(x, y, z)
            end
            self.hud:flash(ok and 'You got out' or 'Cannot get out')
        end)
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

-- The camera follows the car's roof line and swings behind it while driving.
function Session:updateCamera(dt, car)
    local orbit = self.orbit
    orbit:setMode('car', car.rheading or car.heading)
    orbit:follow(dt, car.rheading or car.heading, car.speed)
    orbit:update(car.rx or car.x, (car.ry or car.y) + 1.3, car.rz or car.z)
end

-- Third-person camera around the on-foot player: the StareShooter pivot (chest height of the
-- interpolated body) and its distance.
function Session:updateWalkerCamera(dt, walker)
    local orbit = self.orbit
    orbit:setMode('walk')
    orbit:follow(dt, nil, 0)
    local height = self.walker and self.walker.height or 2
    orbit:update(
        walker.rx or walker.x,
        (walker.ry or walker.y) + 1 + (height - 2) / 2 + 0.5,
        walker.rz or walker.z
    )
end

-- With the window unfocused only the network side runs, so a hosted game keeps answering players.
function Session:updateInBackground(dt)
    if self.server or self.client then
        self:updateNetwork(dt)
    end
end

-- Two-finger pinch zooms the camera (touch screens); the rules live in controller/pinch.lua.
function Session:pointerpressed(id, x, y)
    Pinch.pressed(self, id, x, y)
end

function Session:pointermoved(id, x, y)
    Pinch.moved(self, id, x, y)
end

function Session:pointerreleased(id)
    Pinch.released(self, id)
end

Session.pointercancelled = Session.pointerreleased

-- Feeds the keys to the walker, and keeps its riding state in step with the seat the server gave.
function Session:updateWalker(dt, car, seat)
    local walker = self.walker
    if not walker then
        return
    end
    -- Keys, joystick and the toggles are read by the input (controller/input.lua).
    self.jumpHeld = math.max(0, (self.jumpHeld or 0) - dt)
    walker.cameraYaw = math.rad(self.orbit.yaw)
    if car then
        walker:setSeat(car.x, car.y - car.config.rideHeight + 0.5, car.z)
        local wanted = seat == 1 and 'drive' or 'passenger'
        if walker.fsm.name ~= wanted then
            walker:enterCar(seat)
        end
    elseif walker:isRiding() then
        walker:place(walker.model.x, walker.model.y + 0.5, walker.model.z)
    end
end

-- Tab / the menu button: the cursor is back (open) or captured again (closed).
function Session:onMenuToggled(open)
    self.hud:setMenuOpen(open)
    self.social:setMenuOpen(open)
    if open and self.voice then
        self.social:setMicStatus(self.voice:getStatus())
    end
    self:refreshPlayers()
end

-- Push-to-talk (V, desktop only) and the speaking indicator.
function Session:updateVoice(dt)
    local voice = self.voice
    if not voice or self.mode ~= 'playing' then
        return
    end
    local input = self.scene.input
    local held = not input.touchDevice
        and input:playing()
        and katsa.keyboard.isDown(input.talkKey or 'v')
    if held and not self.micWarned and voice:getStatus() ~= 'ready' then
        self.micWarned = true -- once per session: the reason stays in the player list
        self.hud:flash('Voice chat: ' .. voice:getStatus())
    end
    voice:setTalking(held == true)
    voice:update(dt)
    local meters = {}
    local players = self.client:getPlayers()
    for _, meter in ipairs(voice:getMeters()) do
        for _, player in ipairs(players) do
            if player.id == meter.id then
                meter.name = player.name
            end
        end
        if meter.mine or meter.name then
            meters[#meters + 1] = meter
        end
    end
    self.social:setSpeaking(meters)
end

-- Rebuilds the player list (names, [HOST] tag, Kick buttons for the host).
function Session:refreshPlayers()
    local client = self.client
    if client and self.social.open then
        self.social:setPlayers(client:getPlayers(), client.hostId, client:getPlayerId())
    end
end

-- Physics of the hosted or driven cars and the network traffic of the server and client.
function Session:updateNetwork(dt)
    local profiler = self.scene.manager.profiler
    local stamp = profiler:begin()
    if self.server then
        -- The hosted cars are rigid bodies: step the world, then let the server read them.
        self.scene.physics:update(dt)
        profiler:finish('Cars: physics', stamp)
        stamp = profiler:begin()
        self.server:update(dt)
        profiler:finish('Cars: server', stamp)
    elseif self.client and self.client:simulates() then
        -- A joined player simulates the car it drives and keeps stand-ins for the others.
        self.scene.physics:update(dt)
        self.client:afterPhysics()
        profiler:finish('Cars: physics', stamp)
    end
    stamp = profiler:begin()
    if self.client then
        self.client:update(dt)
    end
    profiler:finish('Cars: client', stamp)
    stamp = profiler:begin()
    self:updateRenderPoses()
    self:watchJumps(dt)
    profiler:finish('Cars: render poses', stamp)
end

local JUMP_METERS = 2.5 -- a drawn car moving this far in one frame is a visible jump
local JUMP_LOG_INTERVAL = 0.25

-- Diagnostic for choppy cars: logs a car that jumps between two frames together with the frame
-- time, so the console export tells a hitch (large dt) from a data problem (normal dt).
function Session:watchJumps(dt)
    local client = self.client
    if not client then
        return
    end
    local now = katsa.timer.getTime()
    local last = self.jumpLast
    if not last then
        last = {}
        self.jumpLast = last
    end
    for netId, car in pairs(client.cars) do
        local x, z = car.rx or car.x, car.rz or car.z
        local previous = last[netId]
        if previous and x and z and dt < 0.1 then
            local moved = math.sqrt((x - previous[1]) ^ 2 + (z - previous[2]) ^ 2)
            if moved > JUMP_METERS and now - (self.jumpLogged or 0) > JUMP_LOG_INTERVAL then
                self.jumpLogged = now
                katsa.log.warn(
                    ('Car %d jumped %.1f m in one frame (frame %.0f ms, server time %.2f, ping %d ms)'):format(
                        netId,
                        moved,
                        dt * 1000,
                        client.client:getServerTime(),
                        client.client:getPing()
                    ),
                    'multiplayerCars',
                    false
                )
            end
        end
        last[netId] = { x, z }
    end
end

-- Bodies simulated by this process are drawn between their last two physics steps.
function Session:updateRenderPoses()
    local physics = self.scene.physics
    local alpha = physics and physics.interpolationAlpha or 1
    local function pose(model, simulated)
        if simulated then
            RenderPose.sample(model)
            RenderPose.apply(model, alpha)
        elseif model._renderPose then
            RenderPose.clear(model)
        end
    end
    local client = self.client
    if client then
        for netId, car in pairs(client.cars) do
            -- Only a car this client's own physics world simulates is blended with the step alpha.
            -- On the hosting machine the client car is a network replica, already interpolated per
            -- frame from snapshots; blending it again made the drawn motion alternate between
            -- half and double steps.
            local body = client.bodies[netId]
            -- A car the local server simulates is read from the server (client:isMirrored).
            pose(car, (body ~= nil and body.mode == 'dynamic') or client.client:isMirrored(netId))
        end
        for _, walker in pairs(client.walkers) do
            local own = self.walker ~= nil and walker == self.walker.model
            if own and not self.walker:isRiding() then
                -- The local character is drawn from its interpolated body, as in StareShooter.
                local x, y, z, heading, walk, crouch = self.walker:renderPose()
                walker.rx, walker.ry, walker.rz = x, y, z
                walker.rheading, walker.rwalk, walker.rcrouch = heading, walk, crouch
            elseif walker.rx then
                RenderPose.clear(walker)
                walker.rwalk, walker.rcrouch = nil, nil
            end
        end
    end
end

function Session:update(dt)
    local keys = self.scene.input.actions.keys
    self:updateNetwork(dt)
    self:updateVoice(dt)
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
            self.social.root.visible = true
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
    self:updateWalker(dt, car, seat)
    self.hud:setOnFoot(car == nil)
    self:buildQueuedView()
    for _, view in pairs(self.views) do
        view:update(dt)
    end
    for _, view in pairs(self.walkerViews) do
        view:update(dt)
    end
    if self.client.botRoute then
        self:updateBotRoute()
    end
    local walker = self.client.ownWalker
    if not car and walker then
        self:updateWalkerCamera(dt, walker)
        self.social:update()
        self.hud:update(dt, {
            speed = walker.speed,
            nitro = 0,
            info = 'On foot  -  E near a car to get in  -  ping '
                .. math.floor(self.client:getPing())
                .. ' ms',
        })
    end
    if car then
        self:updateCamera(dt, car)
        local players = 0
        for _ in pairs(self.client.client.players) do
            players = players + 1
        end
        self.social:update()
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
