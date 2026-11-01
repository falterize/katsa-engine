return function(test)
    local Physics = require('source.engine.physics')
    local World3D = require('source.engine.world.world')
    local Resources = require('source.engine.core.resources')
    local Math = require('source.engine.math.math3d')

    local function check(v, msg)
        test:check(v, msg)
    end

    local function near(a, b)
        return math.abs(a - b) < 0.001
    end
    local resources = Resources.new(require('source.game.data.manifest'))
    local settings = require('source.game.data.settings').create()
    settings.sky.enabled = false
    settings.gizmos.enabled = false
    settings.fog.enabled = false
    local world = World3D.new(resources, settings)
    local physics = Physics.new({ gravity = { 0, 0, 0 }, interpolate = true })
    world.physics = physics
    local body = world:create(
        'Body3D',
        { position = { 0, 0, 80 }, linearDamping = 0, angularDamping = 0, size = { 2, 2, 2 } }
    )
    local mesh = world:create(
        'Mesh3D',
        { name = 'InterpolatedMesh', size = { 2, 2, 2 }, position = { 3, 0, 0 }, texture = 'white' },
        body
    )
    local socket = world:create('Attachment3D', { position = { 3, 0, 0 } }, body)
    body.body:setVelocity({ 120, 0, 0 })
    physics:update(1.5 / 60)
    check(
        near(body:getWorldPosition()[1], 2) and near(body:getRenderWorldPosition()[1], 1),
        'Render interpolation blends fixed-step poses without changing the authoritative position'
    )
    check(
        near(mesh:getRenderWorldPosition()[1], 4) and near(mesh:getWorldPosition()[1], 5),
        'Visual children inherit the blended pose while gameplay reads stay exact'
    )
    check(
        near(socket:getRenderWorldPosition()[1], 4),
        'Attachment3D visual transform inherits interpolation'
    )
    local camera = world:addCamera()
    camera:update(640, 360)
    local board = world:create('BillboardUI', {
        name = 'InterpolatedBoard',
        adornee = socket,
        position = { 0, 0, 0 },
        size = { 0, 60, 0, 30 },
        onTop = true,
    })
    board:update(world, camera)
    check(
        near(board.anchorWorldPosition[1], 4),
        'BillboardUI anchor follows the displayed Attachment3D pose'
    )
    check(
        near(board:getWorldPosition()[1], 5),
        'BillboardUI spatial getter preserves the authoritative support pose'
    )
    world:updateObject(mesh, true)
    check(near(mesh.matrix[4], 4), 'Mesh3D render matrix uses interpolated body pose')
    local hit = physics:raycast({ 2, 0, 70 }, { 2, 0, 90 })
    check(
        hit and hit.body == body.body and near(body:getWorldPosition()[1], 2),
        'Physical raycast uses the exact solver pose independently of rendered geometry'
    )
    world:updateObject(mesh)
    check(
        near(mesh.matrix[4], 5),
        'Authoritative object update restores exact geometry after a render update'
    )
    local renderer = require('source.engine.graphics.pipeline.renderer').new(resources)
    settings.shadows.enabled = true
    world:create(
        'PointLight3D',
        { position = { 0, 20, 80 }, range = 200, radius = 5, castShadow = true }
    )
    world:create('Mesh3D', {
        name = 'InterpolationGround',
        kind = 'plane',
        position = { 0, -5, 80 },
        size = { 100, 1, 100 },
        texture = 'white',
    })
    renderer:draw(world, camera, 0)
    check(
        near(mesh.matrix[4], 4) and renderer.shadows.drawCalls > 0,
        'Main render and shadow passes consume the same interpolated geometry transform'
    )
    local projectedX, projectedY = camera:project(mesh:getRenderWorldPosition())
    local picked =
        require('source.engine.world.picking').raycast(world, camera, projectedX, projectedY)
    check(picked == mesh, 'Visual triangle picking follows the displayed geometry')
    check(
        near(body:getWorldPosition()[1], 2),
        'Rendering shadows cannot write the displayed pose back into physics'
    )
    local oldMatrix = body:getRenderWorldMatrix()
    local oldPose = body.body._renderPose
    body:getRenderWorldMatrix()
    check(
        body.body._renderPose == oldPose and body:getRenderWorldMatrix() == oldMatrix,
        'Render pose buffers are reused between draws'
    )
    body.body:teleport({ 40, 0, 80 }, { 0, 0, 179 })
    check(
        near(body:getRenderWorldPosition()[1], 40),
        'Teleport resets interpolation history without a visible sweep'
    )
    body.body:setVelocity({ 0, 0, 0 })
    body.body.raw:setAngularVelocity(Physics.backend.Vec3.new(0, 0, math.rad(120)))
    physics:update(1 / 60)
    local m = body:getRenderWorldMatrix()
    check(
        m[1] < -0.999 and near(m[1] ^ 2 + m[5] ^ 2 + m[9] ^ 2, 1),
        'Quaternion interpolation crosses the 180 degree boundary through the short rotation arc'
    )
    local attachedCamera = world:addCamera({ position = { 0, 2, 0 } }, body)
    attachedCamera:update(640, 360)
    check(
        near(attachedCamera.worldPosition[1], attachedCamera:getRenderWorldPosition()[1]),
        'Camera3D projection uses the same visual body pose as its attachments'
    )
    physics.paused = true
    check(
        near(body:getRenderWorldMatrix()[1], body:getWorldMatrix()[1]),
        'Paused simulation displays its latest authoritative pose'
    )
    physics.paused = false
    check(
        near(body:getRenderWorldMatrix()[1], body:getWorldMatrix()[1]),
        'Resuming without a fixed step cannot rewind the displayed pose'
    )
    physics:setInterpolation(false)
    check(
        near(body:getRenderWorldPosition()[1], body:getWorldPosition()[1])
            and not body.body._renderPose,
        'Disabling interpolation releases history and immediately uses exact poses'
    )
    world:updateObject(mesh, true)
    check(
        near(mesh.matrix[4], mesh:getWorldPosition()[1]),
        'Disabling interpolation invalidates the cached render transform immediately'
    )
    physics:update(1 / 60)
    physics:setInterpolation(true)
    check(
        near(body:getRenderWorldMatrix()[1], body:getWorldMatrix()[1]),
        'Re-enabling interpolation resets history after unrendered steps'
    )
    check(not pcall(physics.update, physics, -1), 'Negative frame delta is rejected')
    check(
        not pcall(Physics.new, { maxTriggerPairs = 0 })
            and not pcall(Physics.new, { maxSteps = 1.5 }),
        'Fixed-step and trigger budgets reject invalid settings'
    )
    local sensor = world:create(
        'Body3D',
        { bodyType = 'Static', position = { 200, 0, 80 }, size = { 12, 12, 12 }, isTrigger = true }
    )
    local nearby = world:create(
        'Body3D',
        { bodyType = 'Static', position = { 200, 0, 80 }, size = { 2, 2, 2 } }
    )
    for i = 1, 100 do
        world:create(
            'Body3D',
            { bodyType = 'Static', position = { i * 20, 500, 80 }, size = { 2, 2, 2 } }
        )
    end
    local entered, exited = 0, 0
    local nearbyBody = nearby.body
    sensor:connect('triggerEntered', function(other)
        if other == nearbyBody then
            entered = entered + 1
        end
    end)
    sensor:connect('triggerExited', function(other)
        if other == nearbyBody then
            exited = exited + 1
        end
    end)
    physics:update(1 / 60)
    check(
        entered == 1 and physics.stats.triggerCandidates == 1 and physics.stats.triggerQueries == 1,
        'Trigger BVH query excludes 100 distant bodies before narrow phase'
    )
    check(
        physics.stats.triggerPairs == 1
            and physics.stats.solverMilliseconds >= 0
            and physics.stats.triggerMilliseconds >= 0,
        'Profiler exposes solver time and exact trigger work separately'
    )
    sensor.body:set({ isTrigger = false })
    physics:update(1 / 60)
    check(
        exited == 1 and not physics.triggerBodies[sensor.body],
        'Disabling trigger mode emits exit and unregisters the sensor'
    )
    sensor.body:set({ isTrigger = true })
    physics:update(1 / 60)
    check(entered == 2, 'Re-enabled trigger queries current overlaps')
    nearby:destroy()
    physics:update(1 / 60)
    check(exited == 2, 'BVH sensor queries report exit after removal of an overlapping body')
    sensor:destroy()
    physics:update(1 / 60)
    check(
        physics.stats.triggerQueries == 0 and physics.stats.triggerCandidates == 0,
        'No sensors means no trigger queries or retained candidate work'
    )
    physics:release()
    world:release()
    resources:release()
end
