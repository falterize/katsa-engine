local Clock = require('source.engine.world.clock')
local Properties = require('source.engine.editor.inspectors.properties')
local References = require('source.engine.editor.inspectors.nodeReferences')
local Application = require('source.game.runtime.application')

local Tests = {}

local function findField(target, key)
    for _, field in ipairs(Properties.list(target)) do
        if field.key == key then
            return field
        end
    end
end

function Tests.run(tester)
    local world, ui, physics, body, release = tester:environment()
    local other = world:create('World2D', { name = 'Independent2D', timeScale = 0.5 })
    other:createPhysics({ gravity = { 0, 0 } })
    local a = body(100, 100)
    local b = other:create('Body2D', { position = { 100, 100 }, linearDamping = 0 })
    a.body:setVelocity({ 60, 0 })
    b.body:setVelocity({ 60, 0 })
    world:createPhysics({ backend = 'oimo', gravity = { 0, 0, 0 } })
    local spatial = world:create('Body3D', { position = { 0, 0, 0 }, linearDamping = 0 })
    spatial.body:setVelocity({ 1, 0, 0 })
    world:registerNodeType('ClockScript2D', {
        base = 'Node2D',
        update = function(node, dt)
            node.elapsed = (node.elapsed or 0) + dt
        end,
    })
    local scriptA = ui:create('ClockScript2D', {})
    local scriptB = other:create('ClockScript2D', {})
    world.root.timeScale = 0
    for _ = 1, 60 do
        ui:update(1 / 60, 1 / 60)
        other:update(1 / 60, 1 / 60)
        world.physics:update(Clock.delta(world.root, 1 / 60))
        world:updateNodes(Clock.delta(world.root, 1 / 60))
    end
    tester:check(
        math.abs(a.position[1] - 160) < 0.1,
        'World2D continues when its enclosing World3D is paused'
    )
    tester:check(
        math.abs(b.position[1] - 130) < 0.1,
        'A second World2D has an independent fractional time scale'
    )
    tester:check(spatial.position[1] == 0, 'World3D timeScale zero freezes only its simulation')
    tester:check(
        math.abs(scriptA.elapsed - 1) < 0.01 and math.abs(scriptB.elapsed - 0.5) < 0.01,
        'Processed Node2D scripts use their own World2D clocks while World3D is paused'
    )
    world.root.timeScale, ui.timeScale, other.timeScale = 1, 0, 2
    local time = ui.time
    for _ = 1, 60 do
        ui:update(1 / 60, 1 / 60)
        other:update(1 / 60, 1 / 60)
        world.physics:update(Clock.delta(world.root, 1 / 60))
        world:updateNodes(Clock.delta(world.root, 1 / 60))
    end
    tester:check(
        math.abs(a.position[1] - 160) < 0.1 and ui.time == time,
        'Pausing World2D freezes its physics and animation clock'
    )
    tester:check(
        math.abs(b.position[1] - 250) < 0.1,
        'Another World2D can run at double speed concurrently'
    )
    tester:check(spatial.position[1] > 0.9, 'World3D continues while World2D is paused')
    tester:check(
        math.abs(scriptA.elapsed - 1) < 0.01 and math.abs(scriptB.elapsed - 2.5) < 0.01,
        'Changing World2D time scales affects scripts without changing other worlds'
    )
    world:registerNodeType('ClockScriptNode', {
        base = 'Node',
        update = function(node, dt)
            node.elapsed = (node.elapsed or 0) + dt
        end,
    })
    local movable = world:create('ClockScriptNode', {}, ui)
    movable:setParent(world.root)
    world:updateNodes(0.1)
    tester:check(
        math.abs(movable.elapsed - 0.1) < 0.001,
        'Reparenting a script changes its clock owner without retaining the old UI clock'
    )
    local field = findField(ui, 'timeScale')
    tester:check(field and field.kind == 'number', 'Workspace exposes World2D timeScale')
    tester:check(
        Properties.set({ world = world }, ui, field, '0.25') and ui.timeScale == 0.25,
        'Workspace edits World2D timeScale through the common inspector'
    )
    field = findField(a, 'position')
    tester:check(
        field and field.kind == 'vector',
        'Body2D position uses the standard vector editor'
    )
    tester:check(
        Properties.set({ world = world }, a, field, '175', 1)
            and math.abs(a.body:getPosition() - 175) < 0.01,
        'Editing a Body2D position synchronizes its native pose'
    )
    local camera = ui:create('Camera2D', {})
    tester:check(
        findField(camera, 'followTarget').kind == 'node',
        'Camera2D target uses the common node picker'
    )
    tester:check(
        References.accepts(camera, 'followTarget', a)
            and not References.accepts(camera, 'followTarget', b),
        'Camera2D target picking respects World2D ownership'
    )
    local anchor = body(300, 100, 'Static')
    local p = ui:create('Attachment2D', {}, anchor)
    local q = ui:create('Attachment2D', {}, a)
    local rope =
        ui:create('RopeConstraint2D', { attachment0 = p, attachment1 = q, maxLength = 200 })
    field = findField(rope, 'attachment1')
    tester:check(
        Properties.set({ world = world }, rope, field, p),
        'Workspace accepts dimension-correct constraint attachments'
    )
    local p3D = world:create('Attachment3D', {}, spatial)
    tester:check(
        not Properties.set({ world = world }, rope, field, p3D),
        'Workspace rejects a 3D attachment on a 2D constraint'
    )
    ui.timeScale = -1
    tester:check(
        not pcall(ui.update, ui, 1 / 60, 1 / 60),
        'World2D timeScale validation rejects negative values'
    )
    ui.timeScale = 1
    release()

    for _, name in ipairs({ 'physics2D', 'physicsMixed' }) do
        local scene = Application.new(tester.manager, name)
        scene:load()
        tester:check(
            scene.workspace and scene.navigation and scene.toolsPanel and scene.debugOverlay,
            name .. ': the standard Workspace, navigation, Tools and Debug are installed'
        )
        scene:keypressed('f2')
        tester:check(scene.workspace.opened, name .. ': F2 opens Workspace')
        scene:keypressed('f2')
        scene:keypressed('f4')
        tester:check(scene.debugOverlay.visible, name .. ': F4 opens the shared Debug menu')
        scene.debugOverlay.visible = false
        scene.world.root.timeScale = 0
        scene.ui.timeScale = 1
        local ball = scene.demo.ball
        ball.body:teleport(700, 400)
        ball.body:setVelocity({ 60, 0 })
        for _ = 1, 10 do
            scene:update(1 / 60, 1 / 60)
        end
        tester:check(
            ball.position[1] > 705,
            name .. ': the runtime does not apply the 3D clock to 2D physics'
        )
        scene.ui.timeScale = 0
        local x, y = ball.body:getPosition()
        for _ = 1, 5 do
            scene:update(1 / 60, 1 / 60)
        end
        local px, py = ball.body:getPosition()
        tester:check(
            x == px and y == py,
            name .. ': the runtime respects the World2D pause independently'
        )
        scene:draw()
        scene:release()
    end
end

return Tests
