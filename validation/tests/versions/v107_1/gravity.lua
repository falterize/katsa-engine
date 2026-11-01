local Properties = require('source.engine.editor.inspectors.properties')
local Tests = {}

local function near(a, b)
    return math.abs(a - b) < 0.001
end

function Tests.run(tester)
    local world, ui, physics, body, release = tester:environment()
    tester:check(
        ui.gravity == 0 and #ui.gravityDirection == 2,
        'Existing zero-gravity 2D solver options populate World2D properties'
    )
    local item = body(100, 100)
    item.body:sleep()
    ui.Gravity, ui.GravityDirection = 120, { 2, 0 }
    ui:update(1 / 60)
    local x, y = physics:getGravity()
    local vx = item.body:getLinearVelocity()
    tester:check(
        near(x, 120) and near(y, 0) and near(vx, 2),
        'World2D magnitude and normalized direction wake and accelerate sleeping bodies'
    )
    local other = world:create('World2D', { gravity = 60, gravityDirection = { 0, -2 } })
    other:createPhysics()
    x, y = other.physics2D:getGravity()
    tester:check(
        near(x, 0) and near(y, -60) and ui.gravity == 120,
        'Each World2D owns independent gravity settings authored before physics creation'
    )
    ui.gravityDirection = { 0, 0 }
    ui:update(0)
    x, y = physics:getGravity()
    tester:check(x == 0 and y == 0, 'A zero gravity direction disables acceleration')
    physics:setGravity(0, -80)
    tester:check(
        near(ui.gravity, 80) and near(ui.gravityDirection[2], -1),
        'Direct Physics2D gravity writes keep inspector properties synchronized'
    )
    local field
    for _, candidate in ipairs(Properties.list(ui)) do
        if candidate.key == 'gravity' then
            field = candidate
        end
    end
    tester:check(
        field and not Properties.set(nil, ui, field, '-1'),
        'Workspace rejects negative gravity magnitude'
    )
    release()
    for _, backend in ipairs({ 'oimo', 'jolt' }) do
        world, ui, physics, body, release = tester:environment()
        local solver = world:createPhysics({ backend = backend, gravity = { 0, -120, 0 } })
        tester:check(
            near(world.root.gravity, 120) and world.root.gravityDirection[2] == -1,
            backend .. ': World3D preserves existing vector gravity settings'
        )
        local object = world:create('Body3D', { position = { 0, 10, 0 }, linearDamping = 0 })
        object.body.raw:sleep()
        world.root.Gravity, world.root.GravityDirection = 120, { 2, 0, 0 }
        solver:update(1 / 60)
        x, y = solver:getGravity()
        local velocity = object.body:getVelocity()
        tester:check(
            near(x, 120) and near(y, 0) and near(velocity[1], 2),
            backend .. ': World3D gravity edits reach the native solver and wake bodies'
        )
        solver:setGravity({ 0, 0, -60 })
        tester:check(
            near(world.root.gravity, 60) and near(world.root.gravityDirection[3], -1),
            backend .. ': Direct gravity API keeps World3D properties synchronized'
        )
        world.root.gravity = 0
        solver:update(0)
        x, y = solver:getGravity()
        local _, _, z = solver:getGravity()
        tester:check(
            x == 0 and y == 0 and z == 0,
            backend .. ': zero magnitude disables native gravity'
        )
        release()
    end
end

return Tests
