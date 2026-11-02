-- multiplayerCars scene end to end on the real renderer: host, connect, drive, bot, dents.
-- Set KATSA_CARS_SHOT=<dir> to save screenshots of the run.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

function Tests:shot(name)
    local dir = os.getenv('KATSA_CARS_SHOT')
    if dir then
        katsa.graphics.captureScreenshot(dir .. '/' .. name .. '.png')
    end
end

function Tests:startRemote()
    local World3D = require('source.engine.world.world')
    local world = World3D.new(self.host.world.resources, nil, {
        physics = { unitsPerMeter = 1, gravity = { 0, -9.81, 0 }, backend = 'jolt' },
    })
    local Session = getmetatable(self.session).__index
    Session.ArenaView.buildPhysics({ world = world })
    local remote = { world = world, throttle = 0 }
    remote.client = Session.GameClient.new({}, {
        address = '127.0.0.1',
        port = self.port,
        name = 'Remote',
        world = world,
        input = function()
            return { throttle = remote.throttle, steer = 0 }
        end,
    })
    remote.client:connect()
    self.remote = remote
end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if self.maxTilt and frame > 320 and frame < 384 then
        local _, car = self.session.client:getCar()
        if car then
            -- Angles are replicated as 0..360.
            for _, angle in ipairs({ car.roll or 0, car.pitch or 0 }) do
                angle = angle % 360
                self.maxTilt = math.max(self.maxTilt, math.min(angle, 360 - angle))
            end
        end
    end
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load()
        self.session = self.host.demo
        self.manager.profiler:startRecording({ scene = 'multiplayerCars' })
        self:check(self.session.mode == 'menu', 'cars scene starts at the menu')
        local ground
        for _, node in ipairs(self.host.world.root:getDescendants()) do
            if node.name == 'GroundBody' then
                ground = node
            end
        end
        self:check(
            self.host.world.physics ~= nil and ground ~= nil and ground.body ~= nil,
            'the arena has a physical terrain mesh'
        )
        self.port = 47990 + math.floor(os.clock() * 100) % 9
        self.session:host('Tester', self.port)
    end
    local host, session = self.host, self.session
    if not host then
        return
    end
    host:update(1 / 60, 1 / 60)
    host:draw()
    if self.remote then
        self.remote.world.physics:update(1 / 60)
        self.remote.client:afterPhysics()
        self.remote.client:update(1 / 60)
    end
    if frame == 200 then
        self:check(session.mode == 'playing', 'hosting connects the local client')
        self:check(
            type(host.updateInBackground) == 'function',
            'a hosted game has a background update for when its window loses focus'
        )
        local Manager = require('source.engine.core.sceneManager')
        local updated = 0
        local stub = setmetatable({
            focused = false,
            stack = { { update = function() end, updateInBackground = function() updated = updated + 1 end } },
            frameTime = 0,
            flushTransitions = function() end,
            time = { update = function(_, dt) return dt end },
            journal = {},
        }, Manager)
        stub.update(stub, 0.01)
        self:check(updated == 1, 'the scene manager runs updateInBackground for an unfocused scene')
        local count = 0
        for _ in pairs(session.views) do
            count = count + 1
        end
        self:check(count == 2, 'the player car and the bot are drawn')
        self:shot('start')
        -- The bot only patrols here, so it cannot ram the test drive.
        session.server.bot.sightRadius = 0
    elseif frame == 201 then
        local walker = session.walker
        self:check(
            walker and (walker.fsm.name == 'idle' or walker.fsm.name == 'walk'),
            'the player starts on foot beside their own car (' .. tostring(walker and walker.fsm.name) .. ')'
        )
        self:check(session.client:getCar() == nil, 'nobody is seated at spawn')
        session:changeCar() -- E near the parked car
    elseif frame == 215 then
        local _, car, seat = session.client:getCar()
        self:check(car and seat == 1, 'E gets the player into the driver seat')
        self:check(session.walker.fsm.name == 'drive', 'the walker state machine switches to drive')
        host.input.actions.keys.w = true
    elseif frame == 320 then
        local _, car = session.client:getCar()
        self:check(car and car.speed > 8, 'holding W drives the car')
        self:shot('driving')
        -- Full lock at speed for a second: the car must lean, not tip over.
        host.input.actions.keys.a = true
        self.maxTilt = 0
        -- Dragging orbits the camera; the path debug button shows the bot's route on the client.
        host.input.actions:look(30, 10)
        session.hud.debugPath.onPress()
    elseif frame == 335 then
        self:check(math.abs(session.orbit.yaw) > 1, 'dragging orbits the chase camera')
        self:check(
            session.pathDebug and session.pathMarkers and #session.pathMarkers >= 1,
            'path debug draws the bot route markers on the client'
        )
        self:check(session.hud.debugPath.text == 'Path debug: ON', 'the path debug button shows its state')
        self:shot('pathDebug')
        session.hud.debugPath.onPress()
    elseif frame == 340 then
        local _, car = session.client:getCar()
        car.dents:addImpact({ x = 0, z = 2.1, nx = 0, nz = -1, speed = 15 })
        session.views[session.client:getCar()]:markDirty()
    elseif frame == 350 then
        self:shot('dent')
        require('source.engine.editor.debug.diagnostics').open(host.workspace)
    elseif frame == 356 then
        self:shot('profiler')
        host.workspace.popup:close(false)
        local profiler = self.manager.profiler
        self:check(#profiler.recording.rows > 300, 'the profiler records the running scene')
        local summary = profiler:summary()
        self:check(
            summary.frame.frames > 100 and #summary.stages > 3,
            'stage timings are collected'
        )
        local json = profiler.save(profiler:stopRecording(), 'json')
        self:check(katsa.filesystem.getInfo(json) ~= nil, 'a session profile is written to logs/')
        katsa.filesystem.remove(json)
    elseif frame == 357 then
        local ws = host.workspace
        ws:toggle(true)
        ws.collapsed = setmetatable({}, { __mode = 'k' })
        ws:refreshTree()
    elseif frame == 378 then
        local ws = host.workspace
        self:check(
            #ws.rows > 20 and ws.tree.scrollingDirection == 'XY',
            'Workspace tree lists nodes and scrolls on both axes'
        )
        self:check(
            ws.tree.canvasSize[2] >= ws.tree._width,
            'the tree canvas is at least as wide as its window'
        )
        local deepest = 0
        for _, row in ipairs(ws.rows) do
            deepest = math.max(deepest, row.depth)
        end
        self:check(deepest >= 2, 'nested nodes are listed with their depth')
        self:shot('workspace')
    elseif frame == 380 then
        host.workspace:toggle(false)
    elseif frame == 384 then
        host.input.actions.keys.a, host.input.actions.keys.w = nil, nil
        self:check(
            self.maxTilt < 25,
            'a hard turn at speed does not roll the car (max tilt ' .. ('%.1f'):format(self.maxTilt) .. ')'
        )
        self:check(session.hud.info.text:find('Driving'), 'the HUD shows the seat')
        -- The car is a real rigid body: drive it at the east wall and it must stay inside.
        local netId = session.client:getCar()
        local body = session.server.bodies[netId]
        self:check(
            body and body.node.bodyType == 'Dynamic' and body.node.body:getMass() > 500,
            'the player car is a dynamic Body3D with real mass'
        )
        body:respawn(40, 0, 90)
        self.wall = netId
        host.input.actions.keys.w = true
    elseif frame == 392 then
        local model = session.server.cars[self.wall]
        self:check(
            math.abs(model.heading - 90) < 3,
            'a car spawned with heading 90 faces +x (heading ' .. ('%.0f'):format(model.heading) .. ')'
        )
    elseif frame == 560 then
        local model = session.server.cars[self.wall]
        self:check(
            model.x > 45 and model.x < 61.5 and math.abs(model.z) < 61,
            'the wall stops the car inside the arena (x=' .. ('%.1f'):format(model.x) .. ')'
        )
        self:shot('wall')
        host.input.actions.keys.w = nil
    elseif frame == 580 then
        local model = session.server.cars[self.wall]
        self:check(
            math.abs(model.pitch) < 30 and math.abs(model.roll) < 30 and model.y > 0.3,
            'the car rests on its wheels after the crash'
        )
        session:changeCar() -- E in the car gets out
    elseif frame == 596 then
        local walker = session.walker
        self:check(session.client:getCar() == nil, 'E in a car gets the player out')
        local car = session.server.cars[self.wall]
        local apart = math.sqrt((walker.model.x - car.x) ^ 2 + (walker.model.z - car.z) ^ 2)
        self:check(
            walker.fsm.name ~= 'drive' and apart < 5,
            'the walker stands beside the car it left (' .. ('%.1f'):format(apart) .. ' m)'
        )
        self:shot('exited')
        host.input.actions.keys.w = true
    elseif frame == 640 then
        local view
        for _, v in pairs(session.walkerViews) do
            view = v
        end
        local tracks = view and view.tracks
        self:check(
            tracks and tracks.Walk and tracks.Idle,
            'the character has its Idle/Walk/Crouch/Fall/Jump animation tracks'
        )
        self:check(
            tracks and tracks.Walk.weight > 0.5 and tracks.Idle.weight < 0.5,
            'walking blends the Walk animation in'
        )
        self:shot('walking')
        host.input.actions.keys.w = nil
        self:startRemote()
    elseif frame == 720 then
        local rc = self.remote.client
        rc:sit(rc:findNearbyCar(6))
    elseif frame == 740 then
        local rc = self.remote.client
        local netId, car = rc:getCar()
        local server = session.server
        self:check(netId ~= nil, 'a second player joined and got a car')
        self.remoteId = netId
        self:check(
            rc.bodies[netId] and rc.bodies[netId].mode == 'dynamic',
            'the driver client owns and simulates its car'
        )
        self:check(
            server.bodies[netId].mode == 'follow' and server.server:getAuthority(netId) ~= nil,
            'the server hands the car to the driver and follows its state'
        )
        self.remoteStart = { car.x, car.z }
        self.remote.throttle = 1
    elseif frame == 940 then
        local _, car = self.remote.client:getCar()
        local server = session.server
        local moved = math.sqrt((car.x - self.remoteStart[1]) ^ 2 + (car.z - self.remoteStart[2]) ^ 2)
        local mirror = server.cars[self.remoteId]
        self:check(moved > 10, 'the driver drives its own car (moved ' .. ('%.1f'):format(moved) .. ')')
        self:check(
            math.abs(mirror.x - car.x) < 6 and math.abs(mirror.z - car.z) < 6,
            'the server model follows the driver client'
        )
        self.remote.throttle = 0
        self.remote.client:disconnect()
    elseif frame == 1060 then
        local server = session.server
        self:check(
            server.server:getAuthority(self.remoteId) == nil and server.bodies[self.remoteId].mode == 'dynamic',
            'a car without a driver goes back to server authority'
        )
        self.remote.world.physics:release()
        self.remote = nil
        session:leave()
        self:check(
            session.mode == 'menu' and next(session.views) == nil,
            'leaving returns to the menu'
        )
        host:update(1 / 60, 1 / 60)
        host:draw()
    elseif frame == 1080 then
        host:release()
        print('PASSED ' .. self.count .. ' v108.4 cars scene checks')
        katsa.event.quit()
    end
end

return Tests
