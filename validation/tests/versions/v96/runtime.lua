local T = {}

local function pixels(renderer)
    local image = renderer.canvas:newImageData()
    local bytes = image:getString()
    image:release()
    return bytes
end

local function extra(test)
    local scene =
        assert(test.manager:switch(require('source.game.runtime.game').new, 'animationPhysicsLab'))
    local w, r, c = scene.world, scene.renderer, scene.camera
    w.debug.bones = false
    for _, a in ipairs(w.animators) do
        a.debugEnabled = false
    end
    w.environment.shadows.sourceFadeSeconds = 0
    -- Keep the scene's quality and content. Drain scheduled maps before pixel comparisons.
    for i = 1, 20 do
        test.manager:update(1 / 60)
        test.manager:draw()
    end
    test:check(
        r._frameCache.meshSnapshots and r._frameCache.volatile,
        'Animated/physical worlds keep mesh snapshots without reusing the final frame'
    )
    test:check(
        r.stats.updatedMeshes < #w.objects,
        'Rig simulation leaves static neighboring meshes prepared'
    )
    for i = 1, 4 do
        test.manager:update(1 / 60)
        r:draw(w, c, scene.time, true)
        local expected = pixels(r)
        r:invalidate()
        r:draw(w, c, scene.time, true)
        test:check(
            expected == pixels(r),
            'Incremental dynamic frame matches forced preparation ' .. i
        )
    end
    local parent = w:create('Node3D', { position = { 20, 0, 0 } })
    local body = w:create('Body3D', { position = { 2, 30, 0 }, bodyType = 'Kinematic' }, parent)
    body:update(0)
    local b = body.body
    b:sync()
    local revision = body._propertyRevision
    b:sync()
    body:getWorldMatrix()
    body:getWorldMatrix()
    test:check(
        body._propertyRevision == revision,
        'Repeated parented body reads do not write temporary world positions into local properties'
    )
    parent.position.X = parent.position.X + 7
    b:sync()
    local raw = b.raw:getPosition()
    local p = body:getWorldPosition()
    test:check(
        math.abs(p[1] - raw.x * w.physics.units) < 1e-6,
        'Parent movement invalidates the body-owned inverse cache'
    )
    local collider = w:create('Collider3D', { size = { 2, 3, 4 } }, body)
    local first, key = collider:descriptor(body)
    local second, nextKey = collider:descriptor(body)
    test:check(
        first == second and key == nextKey,
        'Unchanged primitive colliders reuse their descriptor'
    )
    collider.size[2] = 9
    local third, changedKey = collider:descriptor(body)
    test:check(
        third ~= second and third.size[2] == 9 and changedKey ~= key,
        'In-place primitive collider edits replace the cached descriptor immediately'
    )
    parent:destroy()
    test:check(
        body.destroyed and b.destroyed,
        'Destroying the cache owner releases its physical subtree'
    )
    local other = require('source.engine.graphics.pipeline.renderer').new(scene.resources)
    other:draw(w, c, scene.time, true)
    local floor = w.byName.PracticeFloorVisual
    floor.rotation.Y = floor.rotation.Y + 5
    r:draw(w, c, scene.time, true)
    other:draw(w, c, scene.time, true)
    test:check(
        r._frameCache.nodes[floor].chainChanged and other._frameCache.nodes[floor].chainChanged,
        'Two renderers independently observe edits in an animated physical world'
    )
    other:release()
    local Vector3 = require('source.engine.math.vector3')
    for i = 1, 2000 do
        local input = { i, 2, 3 }
        floor.position = input
        input[1] = -1
        floor.size = { 10, 11, 12 }
        floor.scale = { 1, 1, 1 }
        floor.position.X = 4
        floor.size.z = 14
        floor.scale.y = 2
        assert(
            floor.position.x == 4 and floor.size.Z == 14 and floor.scale[2] == 2,
            'Repeated whole-value assignment lost a named component'
        )
        local copy = Vector3.new(i, 2, 3):clone()
        assert(copy.X == i and copy:toArray()[3] == 3, 'Constructor/clone lost value data')
    end
    test:check(
        true,
        'Managed constructor and property assignment stress preserves copies and aliases'
    )
    local combined =
        assert(test.manager:switch(require('source.game.runtime.game').new, 'combined'))
    local Managed = require('source.engine.math.managedValue')
    for _, object in ipairs(combined.world.objects) do
        for _, key in ipairs({ 'position', 'rotation', 'scale', 'size' }) do
            assert(
                Managed.is(object[key]) and rawget(object, key) == nil,
                'Node initialization left an untracked authored field: '
                    .. object.name
                    .. '.'
                    .. key
            )
        end
    end
    test:check(true, 'Every stress-scene mesh initializes all transform values as managed storage')
end

function T.new(manager)
    local base = require('validation.tests.versions.v89.runtime').new(manager)
    print(
        'RUNTIME',
        jit and jit.version or _VERSION,
        jit and jit.status() or false,
        jit and jit.arch or 'Lua'
    )
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v96 regression/integration checks')
    end
    return base
end

return T
