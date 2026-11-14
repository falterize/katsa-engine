local T = {}

local function matrixChecks(test)
    local M = require('source.engine.math.math3d')

    local function reference(a, b)
        local out = {}
        for row = 0, 3 do
            for col = 0, 3 do
                local i = row * 4
                out[i + col + 1] = a[i + 1] * b[col + 1]
                    + a[i + 2] * b[col + 5]
                    + a[i + 3] * b[col + 9]
                    + a[i + 4] * b[col + 13]
            end
        end
        return out
    end

    local function copy(a)
        local b = {}
        for i = 1, 16 do
            b[i] = a[i]
        end
        return b
    end
    for seed = 1, 50 do
        local a, b = {}, {}
        for i = 1, 16 do
            a[i] = math.sin(seed + i) * 3
            b[i] = math.cos(seed - i) * 2
        end
        local expected = reference(a, b)
        local left, right = copy(a), copy(b)
        local normal = M.multiply(a, b)
        M.multiply(left, b, left)
        M.multiply(a, right, right)
        local squared = copy(a)
        local square = reference(a, a)
        M.multiply(squared, squared, squared)
        for i = 1, 16 do
            assert(
                normal[i] == expected[i]
                    and left[i] == expected[i]
                    and right[i] == expected[i]
                    and squared[i] == square[i],
                'Matrix product or output alias changed arithmetic'
            )
        end
    end
    test:check(true, 'Matrix products preserve scalar reference arithmetic and both output aliases')
end

local function extra(test)
    matrixChecks(test)
    local scene =
        assert(test.manager:switch(require('source.game.runtime.game').new, 'animationPhysicsLab'))
    local w = scene.world
    local parent = w:create('Node3D', { position = { 15, 0, 0 } })
    local node = w:create('Body3D', { bodyType = 'Kinematic', position = { 2, 35, 0 } }, parent)
    local body = node.physics
    body:sync()
    local A = require('source.engine.math.affine')
    local euler, calls = A.euler, 0
    A.euler = function(...)
        calls = calls + 1
        return euler(...)
    end
    for _ = 1, 6 do
        body:sync()
        node:getWorldMatrix()
    end
    A.euler = euler
    test:check(
        calls == 0,
        'Repeated exact body reads skip Euler reconstruction after validating the same pose'
    )
    node.position.X = node.position.X + 4
    body:sync()
    local raw = body.raw:getPosition()
    test:check(
        math.abs(raw.x * w.physics.units - node:getWorldPosition()[1]) < 1e-6,
        'Authored edits invalidate the exact body-pose cache'
    )
    raw.x = raw.x + 0.5
    body.raw:setPosition(raw)
    body:sync()
    test:check(
        math.abs(node:getWorldPosition()[1] - raw.x * w.physics.units) < 1e-6,
        'Direct solver pose edits remain visible between simulation steps'
    )
    parent.position.Y = 8
    body:sync()
    local point = node:getWorldPosition()
    test:check(
        math.abs(point[2] - raw.y * w.physics.units) < 1e-6,
        'Parent movement invalidates cached local physical poses'
    )
    local expected = node.physicsMatrix[4]
    node.physicsMatrix[4] = expected + 12
    body:sync()
    test:check(
        math.abs(node.physicsMatrix[4] - expected) < 1e-6,
        'Mutable physics output matrices are not trusted without comparison'
    )
    body:teleportLocal(node.position, node.rotation)
    test:check(
        body._poseSnapshot ~= nil,
        'Teleporting to the same pose still refreshes authored synchronization state'
    )
    local oldLinear, oldAngular = body.raw:getLinearVelocity(), body.raw:getAngularVelocity()
    local linear, angular = body.raw:getLinearVelocity(), body.raw:getAngularVelocity()
    linear.x, linear.y, linear.z = 3, 5, 7
    angular.x, angular.y, angular.z = 11, 13, 17
    body.raw:setLinearVelocity(linear)
    body.raw:setAngularVelocity(angular)
    local output = body.raw:getPosition()
    body.raw:getAngularVelocityTo(output)
    local allocated = body.raw:getAngularVelocity()
    test:check(
        output.x == allocated.x
            and output.y == allocated.y
            and output.z == allocated.z
            and output.x == 11
            and output.y == 13
            and output.z == 17,
        'Nonallocating angular velocity getter returns angular rather than linear velocity'
    )
    local center = body.raw:getPosition()
    local position = {
        center.x * w.physics.units + 2,
        center.y * w.physics.units + 3,
        center.z * w.physics.units + 4,
    }
    local axis = { 0.2, 0.3, 0.5 }
    local speed = body:pointResponse(position, axis)
    local velocity = body:getVelocity()
    local expectedSpeed = (velocity[1] + 13 * 4 - 17 * 3) * axis[1]
        + (velocity[2] + 17 * 2 - 11 * 4) * axis[2]
        + (velocity[3] + 11 * 3 - 13 * 2) * axis[3]
    test:check(
        math.abs(speed - expectedSpeed) < 1e-9,
        'Reused point response buffers preserve angular point velocity'
    )
    body.raw:setLinearVelocity(oldLinear)
    body.raw:setAngularVelocity(oldAngular)
    local constraint = w.physics.constraints[1]
    constraint:step(1 / 60)
    local endpoint = constraint._endpoint0
    local inverse, position = endpoint.inverse, endpoint.position
    constraint:step(1 / 60)
    test:check(
        endpoint.inverse == inverse and endpoint.position == position,
        'Constraint endpoint buffers are reused without skipping transform queries'
    )
    local source = w:create('Node3D')
    local a = w:create('Mesh3D', { name = 'GeometryCache97A' }, source)
    local b = w:create('Mesh3D', { name = 'GeometryCache97B', position = { 3, 0, 0 } }, source)
    local holder = w:create('Body3D', { bodyType = 'Static' })
    local collider = w:create('Collider3D', { shape = 'Geometry', geometrySource = source }, holder)
    local builder = require('source.engine.physics.3d.modelCollider')
    builder.collect(collider, holder)
    b.parent = w.folders.Geometry
    local parts = builder.collect(collider, holder)
    test:check(
        #parts == 1 and collider._geometryStates[b] == nil and not b.destroyed,
        'Geometry collider caches release live meshes moved outside their source'
    )
    collider.geometrySource = nil
    collider:descriptor(holder)
    test:check(
        collider._geometryStates == nil and collider._geometryOrder == nil,
        'Removing a geometry source clears its tracking references'
    )
    collider.geometrySource = source
    builder.collect(collider, holder)
    collider.shape = 'Box'
    collider:descriptor(holder)
    test:check(
        collider._geometryStates == nil,
        'Switching to a primitive collider clears geometry tracking'
    )
    local Snapshot = require('source.engine.core.valueSnapshot')
    local keys, vectors = { 'visible', 'test97Default' }, { 'position' }
    local old = a._class.test97Default
    a._class.test97Default = 5
    a.visible = false
    local record = {}
    Snapshot.fields(record, a, keys, vectors)
    test:check(
        record.visible == false
            and record.test97Default == 5
            and not Snapshot.fields(record, a, keys, vectors),
        'Inline snapshot reads preserve false values and class defaults'
    )
    a.position.Z = 7
    a._class.test97Default = 8
    test:check(
        Snapshot.fields(record, a, keys, vectors)
            and record.position[3] == 7
            and record.test97Default == 8,
        'Snapshot fallbacks retain managed edits and changed class defaults'
    )
    a._class.test97Default = old
    parent:destroy()
    source:destroy()
    b:destroy()
    holder:destroy()
end

function T.new(manager)
    local base = require('validation.tests.versions.v96.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v97 regression/integration checks')
    end
    return base
end

return T
