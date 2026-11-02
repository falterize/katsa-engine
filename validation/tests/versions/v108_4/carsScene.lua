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

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
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
        self.session:host('Tester', 47990 + math.floor(os.clock() * 100) % 9)
    end
    local host, session = self.host, self.session
    if not host then
        return
    end
    host:update(1 / 60, 1 / 60)
    host:draw()
    if frame == 200 then
        self:check(session.mode == 'playing', 'hosting connects the local client')
        local count = 0
        for _ in pairs(session.views) do
            count = count + 1
        end
        self:check(count == 2, 'the player car and the bot are drawn')
        self:shot('start')
        -- The bot only patrols here, so it cannot ram the test drive.
        session.server.bot.sightRadius = 0
    elseif frame == 201 then
        host.input.actions.keys.w = true
    elseif frame == 320 then
        local _, car = session.client:getCar()
        self:check(car and car.speed > 8, 'holding W drives the car')
        self:shot('driving')
        host.input.actions.keys.w = nil
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
        session:leave()
        self:check(
            session.mode == 'menu' and next(session.views) == nil,
            'leaving returns to the menu'
        )
        host:update(1 / 60, 1 / 60)
        host:draw()
    elseif frame == 590 then
        host:release()
        print('PASSED ' .. self.count .. ' v108.4 cars scene checks')
        katsa.event.quit()
    end
end

return Tests
