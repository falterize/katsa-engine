local Schema = require('source.engine.editor.inspectors.schema')
local Plane = require('source.engine.ui.spatial.plane')
local Tests = {}

local function near(a, b)
    return math.abs(a - b) < 0.001
end

function Tests.run(tester)
    local world, ui, physics, _, release = tester:environment()
    local group = ui:create('Node2D', {
        position = { 128, 128 },
        rotation = 25,
        scale = { 2, 0.75 },
    })
    local item = ui:create('Body2D', {
        position = { 20, 0 },
        rotation = 35,
        scale = { 1.25, 1 },
        bodyType = 'Static',
    }, group)
    local collider = ui:create('Collider2D', {
        position = { 5, -2 },
        rotation = 12,
        size = { 20, 12 },
        scale = { 0.75, 1.4 },
    }, item)
    local visual = ui:create('Button', {
        size = { 1, 0, 1, 0 },
        backgroundColor = { 1, 0, 0 },
        text = '',
    }, collider)
    local keys = table.concat(Schema.keys(group, {}), '|')
    tester:check(
        keys:find('position') and keys:find('rotation') and keys:find('scale'),
        'Node2D exposes position, rotation and Vector2 scale as a spatial group'
    )
    tester:check(
        #group.scale == 2 and group.scale.x == 2 and #world.root.scale == 3,
        '2D and 3D transform scales retain dimension-correct managed vectors'
    )
    ui:update(0)
    local x, y = item.physics:getPosition()
    tester:check(
        near(x, 128 + 40 * math.cos(math.rad(25))) and near(y, 128 + 40 * math.sin(math.rad(25))),
        'Group scale and rotation transform native body positions'
    )
    local a, b, c, d, px, py = collider:getWorldTransform()
    local fixture = item.physics.fixtures[1]
    local insideX, insideY = px + 9 * a + 5 * c, py + 9 * b + 5 * d
    tester:check(
        fixture:testPoint(insideX * physics.factor, insideY * physics.factor)
            and not fixture:testPoint(
                (px + 11 * a + 7 * c) * physics.factor,
                (py + 11 * b + 7 * d) * physics.factor
            ),
        'Rotated nonuniform scale preserves full affine collider geometry'
    )
    local sx, sy = ui:worldToScreen2D(insideX, insideY)
    tester:check(
        ui:hit(sx, sy) == visual,
        'Affine visual hit testing matches scaled physics geometry'
    )
    local lx, ly = Plane.localPoint(ui, collider, sx, sy)
    tester:check(
        near(lx, 19) and near(ly, 1),
        'Pointer inversion preserves sheared local coordinates'
    )
    item:setWorldPose(200, 210, 60)
    x, y = item:getWorldPose()
    tester:check(
        near(x, 200) and near(y, 210),
        'World pose writes invert parent scale and rotation'
    )
    ui:update(0)
    fixture = item.physics.fixtures[1]
    ui:update(0)
    tester:check(
        item.physics.fixtures[1] == fixture,
        'Unchanged affine transforms retain native fixtures'
    )
    group.scale[1] = 3
    ui:update(0)
    tester:check(
        item.physics.fixtures[1] ~= fixture and fixture:isDestroyed(),
        'Editing ancestor scale rebuilds native geometry transactionally'
    )
    local ball =
        ui:create('Body2D', { position = { 600, 600 }, scale = { 2, 1 }, linearDamping = 0 })
    ui:create('Collider2D', { shape = 'Circle', radius = 10 }, ball)
    ui:update(0)
    local inside = physics:overlapPoint({ 618, 600 })
    local outside = physics:overlapPoint({ 600, 611 })
    tester:check(
        #ball.physics.fixtures > 1 and #inside == 1 and #outside == 0,
        'Nonuniformly scaled circles become ellipses with matching point queries'
    )
    ball.scale = { 2, 2 }
    ui:update(0)
    tester:check(
        #ball.physics.fixtures == 1 and ball.physics.fixtures[1]:getShape():getType() == 'circle',
        'Uniform circle scale retains the native analytic circle'
    )
    local current = ball.physics.fixtures[1]
    ball.physics:setVelocity({ 60, 0 })
    for _ = 1, 5 do
        ui:update(1 / 60)
    end
    tester:check(
        ball.physics.fixtures[1] == current,
        'Rigid movement does not rebuild scaled fixtures'
    )
    x, y = ball.physics:getPosition()
    tester:check(
        near(x, 605) and near(y, 600),
        'Scaled dynamic bodies still use world-unit velocity'
    )
    release()
end

return Tests
