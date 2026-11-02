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

-- A screen point where two fingers `width` px apart touch no interactable UI.
function Tests:freeSpot(ui, width)
    local w, h = katsa.graphics.getDimensions()
    for y = h * 0.35, h * 0.8, 20 do
        for x = 20, w - width - 20, 20 do
            if not ui:blocksWorldClick(x, y, true) and not ui:blocksWorldClick(x + width, y, true) then
                return x, y
            end
        end
    end
    return 20, 20
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
        local seen
        stub.time = { update = function(_, dt) return dt * 5 end }
        stub.stack[1].updateInBackground = function(_, dt) seen = dt; updated = updated + 1 end
        stub.update(stub, 0.01)
        self:check(
            seen and math.abs(seen - 0.05) < 1e-9,
            'the background update gets the time-scaled step, so timeScale applies to a hosted game'
        )
        stub.time = { update = function(_, dt) return dt end }
        local full = 0
        stub.stack[1].update = function() full = full + 1 end
        stub.stack[1].settings = { runInBackground = true }
        stub.update(stub, 0.01)
        self:check(full == 1, 'runInBackground in the scene settings keeps the full update')
        stub.stack[1].settings = { runInBackground = false }
        stub.backgroundOverride = true
        stub.update(stub, 0.01)
        self:check(full == 2, 'the debug menu override keeps the full update')
        stub.backgroundOverride = nil
        stub.update(stub, 0.01)
        self:check(
            full == 2 and updated == 3,
            'without the setting an unfocused scene only updates in background'
        )
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
        self:check(car and car.speed > 18, 'holding W accelerates the car briskly (> 18 m/s in under 2 s)')
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
        local walker = session.walker
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
        self:check(
            walker.fsm.name == 'walk' or walker.fsm.name == 'run',
            'walking on the terrain never switches to the fall state (' .. walker.fsm.name .. ')'
        )
        -- Walker gravity follows the physics world's gravity.
        local g = walker:gravityAcceleration()
        local _, wy = session.scene.physics:getGravity()
        self:check(
            math.abs(g - math.abs(wy) * walker.settings.gravityMultiplier) < 1e-6,
            'walker gravity follows the world gravity (' .. ('%.2f'):format(g) .. ' m/s2)'
        )
        -- Phone toggles: tapping Run / Crouch latches the input.
        session.hud.runButton.onPress()
        session.hud.crouchButton.onPress()
        host.input:update(0.016)
        self:check(
            walker.input.sprint and walker.input.crouch,
            'the Run and Crouch buttons latch sprint and crouch'
        )
        session.hud.runButton.onPress()
        session.hud.crouchButton.onPress()
        host.input:update(0.016)
        self:check(
            not walker.input.sprint and not walker.input.crouch,
            'tapping the buttons again releases them'
        )
        -- The on-screen joystick (Move action) drives the car and the walker like the keys.
        local heldW = host.input.actions.keys.w
        host.input.actions.keys.w = nil
        host.input.axisX, host.input.axisY = -0.5, 0.8 -- the on-screen stick
        host.input:update(0.016)
        local drive = session:input()
        self:check(
            math.abs(drive.throttle - 0.8) < 1e-6 and math.abs(drive.steer + 0.5) < 1e-6,
            'the joystick steers the car'
        )
        self:check(
            math.abs(walker.input.forward - 0.8) < 1e-6 and math.abs(walker.input.right + 0.5) < 1e-6,
            'the joystick moves the walker'
        )
        host.input.axisX, host.input.axisY = 0, 0
        host.input.actions.keys.w = heldW
        -- Zoom: buttons and a two-finger pinch move the orbit camera.
        local before = session.orbit.distance
        session.hud.zoomIn.onPress()
        self:check(session.orbit.distance < before, 'the zoom button brings the camera closer')
        session.hud.zoomOut.onPress()
        session.hud.zoomOut.onPress()
        local fx, fy = self:freeSpot(session.scene.ui, 260)
        session:pointerpressed(1, fx, fy)
        session:pointerpressed(2, fx + 100, fy)
        local mid = session.orbit.distance
        session:pointermoved(2, fx + 200, fy)
        self:check(session.orbit.distance < mid, 'spreading two fingers zooms in')
        session:pointerreleased(1)
        session:pointerreleased(2)
        -- The real event paths: the host forwards the wheel and the touches to the scene.
        local wheelBefore = session.orbit.distance
        host:wheelmoved(0, 1)
        self:check(session.orbit.distance < wheelBefore, 'the mouse wheel zooms through the host')
        local pinchBefore = session.orbit.distance
        host:pointerpressed(11, fx, fy)
        host:pointerpressed(12, fx + 100, fy)
        host:pointermoved(12, fx + 220, fy, 120, 0)
        host:pointerreleased(11, fx, fy)
        host:pointerreleased(12, fx + 220, fy)
        self:check(session.orbit.distance < pinchBefore, 'a pinch zooms through the host')
        -- The wheel belongs to the UI over any interactable element; a branch with Interactable
        -- off takes no input, so the camera zooms there again.
        local ui, button = session.scene.ui, session.hud.sitButton
        local bx, by = ui:position(button)
        local sx, sy = ui.offsetX + (bx + 6) * ui.scale, ui.offsetY + (by + 6) * ui.scale
        self:check(ui:blocksWorldClick(sx, sy, true), 'a visible HUD button blocks the camera zoom')
        session.hud.root.interactable = false
        self:check(
            not ui:blocksWorldClick(sx, sy, true),
            'Interactable off on an ancestor frees the wheel for the camera'
        )
        session.hud.root.interactable = true
        -- World TimeScale also paces the server while the window is unfocused.
        local seenStep
        local original = session.updateInBackground
        session.updateInBackground = function(_, dt) seenStep = dt end
        host.world.root.timeScale = 5
        host:updateInBackground(0.1, 0.1)
        host.world.root.timeScale = 1
        session.updateInBackground = original
        self:check(
            seenStep and math.abs(seenStep - 0.5) < 1e-9,
            'the background step is scaled by the world TimeScale'
        )
        self:shot('walking')
        host.input.actions.keys.w = nil
        self:startRemote()
    elseif frame == 641 then
        -- Walk (and sprint) up and down the hills: the fall state must never trigger on terrain.
        local Arena = require('source.game.scenes.multiplayerCars.scripts.game.arena')
        local walker = session.walker
        local keys = host.input.actions.keys
        local runs = { { -48, -10, 90 }, { -30, 10, 180 }, { 10, -35, 90 }, { -5, -40, 90 } }
        local worst = 0
        for _, run in ipairs(runs) do
            for _, sprint in ipairs({ false, true }) do
                walker:place(run[1], Arena.ground(run[1], run[2]) + 0.2, run[2])
                session.orbit.yaw = run[3]
                keys.w = true
                host.input.runToggled = sprint
                local streak, landed = 0, false
                for _ = 1, 360 do
                    session:update(1 / 60)
                    if walker.fsm.name == 'fall' then
                        streak = landed and streak + 1 or streak
                    else
                        landed = true
                        streak = 0
                    end
                    worst = math.max(worst, streak)
                end
            end
        end
        host.input.runToggled = false
        keys.w = nil
        self:check(
            worst <= 2,
            'walking and sprinting over hills never flips to the fall state (' .. worst .. ' frames)'
        )
        -- Standing on a moving body carries the character along with it.
        local platform = session.scene.world:create('Body3D', {
            name = 'TestPlatform',
            bodyType = 'Dynamic',
            size = { 8, 0.5, 8 },
            position = { 0, 40, 0 },
            mass = 4000,
            gravityScale = 0,
            autoSleep = false,
            linearDamping = 0,
            angularDamping = 0,
            rotationFactor = { 0, 0, 0 },
            friction = 0.5,
        })
        walker:place(0, 40.25, 0)
        local startX = 0 -- where the walker was placed
        for _ = 1, 150 do
            platform.body:setVelocity({ 3, 0, 0 })
            session:update(1 / 60)
        end
        local carried = walker.model.x - startX
        local platformMoved = platform.position[1]
        self:check(
            walker.fsm.name ~= 'fall' and math.abs(carried - platformMoved) < 1.5 and carried > 4,
            ('the character rides a moving body (%.1f m of %.1f m)'):format(carried, platformMoved)
        )
        platform:destroy()
        -- The car park: the deck and the ramp are solid, at the heights the navigation assumes.
        local Arena = require('source.game.scenes.multiplayerCars.scripts.game.arena')
        local g = Arena.garage
        local out = {}
        local deck = session.scene.physics:raycast({ -42, 20, -48 }, { -42, -5, -48 }, nil, out)
        self:check(
            deck and math.abs(deck.position[2] - g.deckY) < 0.05,
            'the car park deck is solid at its height (' .. tostring(deck and deck.position[2]) .. ')'
        )
        local ramp = session.scene.physics:raycast({ -18, 20, -49 }, { -18, -5, -49 }, nil, {})
        self:check(
            ramp and math.abs(ramp.position[2] - Arena.deckHeight(-18, -49)) < 0.12,
            'the ramp surface matches its height function (' .. tostring(ramp and ramp.position[2]) .. ' vs ' .. Arena.deckHeight(-18, -49) .. ')'
        )
        -- A hard hit beside a wheel tears it off on the server...
        local hitId, hitCar
        for netId, candidate in pairs(session.server.cars) do
            if candidate.damage then
                hitId, hitCar = netId, candidate
            end
        end
        session.server:addDent(hitId, hitCar, {
            x = -0.9, y = 0.4, z = 1.3, nx = 1, ny = 0, nz = 0.2, speed = 32,
        }, 1e9)
        self:check(hitCar.detached ~= 0, 'a hard hit beside a wheel tears it off (server)')
        self.hitCarId = hitId
        walker:place(-30, 3, -10)
    elseif frame == 700 and self.hitCarId then
        -- ... and every client hides it and sheds a rolling wheel.
        local id = self.hitCarId
        local view = session.views[id]
        local replicated = session.client.cars[id]
        local hidden = 0
        for _, wheel in ipairs(view and view.wheels or {}) do
            hidden = hidden + (wheel.visible == false and 1 or 0)
        end
        self:check(
            replicated and replicated.detached ~= 0 and hidden >= 1 and #view.debris >= 1,
            'the lost wheel replicates: hidden on the car and rolling away as debris'
        )
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
