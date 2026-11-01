return function(test)
    local Node = require('source.engine.nodes')
    local Physics = require('source.engine.physics')
    local Math = require('source.engine.math.math3d')

    local function close(a, b)
        for i = 1, 16 do
            if math.abs(a[i] - b[i]) > 1e-5 then
                return false
            end
        end
        return true
    end
    local root = Node.new('World3D', {})
    local physics = Physics.new({ gravity = { 0, 0, 0 } })
    local mesh = Node.new('Mesh3D', {
        position = { 10, 20, 30 },
        rotation = { 23, 41, -12 },
        size = { 4, 6, 8 },
        scale = {
            2,
            2,
            2,
        },
    }, root)
    local expected = Math.compose(mesh.position, mesh.rotation, mesh.scale)
    local body = physics:addBody(mesh, { type = 'Static' })
    test:check(
        close(mesh:getWorldMatrix(), expected),
        'Oimo initial pose agrees with engine rotation and spatial scale'
    )
    local revision = mesh._transformRevision
    body:sync()
    mesh:getWorldMatrix()
    test:check(
        mesh._transformRevision == revision,
        'Stationary physics synchronization retains transform revision'
    )
    mesh:setLocalTransform({ position = { -5, 3, 9 }, rotation = { -35, 62, 17 } })
    test:check(
        close(mesh:getWorldMatrix(), Math.compose({ -5, 3, 9 }, { -35, 62, 17 }, { 2, 2, 2 })),
        'Physics teleport uses the same Euler convention as rendering'
    )
    -- The uniformly scaled box extends 4,6,8 units from its center.
    physics:update(1 / 60)
    local hit = physics:raycast({ -5, 3, -30 }, { -5, 3, 50 })
    test:check(
        hit and hit.body.object == mesh,
        'Uniformly scaled collider remains queryable after rotated teleport'
    )
    mesh:setLocalTransform({ position = { 0, 0, 0 }, rotation = { 0, 0, 0 } })
    physics:update(1 / 60)
    local edge = physics:raycast({ 3.9, 0, -20 }, { 3.9, 0, 20 })
    local outside = physics:raycast({ 4.1, 0, -20 }, { 4.1, 0, 20 })
    test:check(
        edge and not outside,
        'Collider3D dimensions include uniform spatial scale exactly once'
    )
    test:check(
        not pcall(mesh.setLocalTransform, mesh, { scale = { 3, 3, 3 } }),
        'Live body rejects scale changes requiring rebuild'
    )
    local uneven = Node.new('Mesh3D', { scale = { 1, 2, 1 } }, root)
    test:check(
        not pcall(physics.addBody, physics, uneven, { type = 'Static' }) and not uneven.body,
        'Nonuniform physics scale fails before solver insertion'
    )
    root.scale = { 2, 2, 2 }
    local transformed = Node.new('Mesh3D', {}, root)
    test:check(
        not pcall(physics.addBody, physics, transformed, { type = 'Static' }),
        'Physics rejects transformed World3D roots'
    )
    root.scale = { 1, 1, 1 }
    root:destroy()
    physics:release()
end
