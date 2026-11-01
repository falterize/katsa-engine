local T = {}

local function extra(test)
    local scene = test.manager:switch(require('source.game.runtime.game').new, 'combined')
    local w, r, c = scene.world, scene.renderer, scene.camera
    w.environment.shadows.enabled = false
    local Reference = require('source.engine.core.valueSnapshot')
    local Properties = require('source.engine.graphics.pipeline.propertySnapshot')
    local State = require('source.engine.graphics.pipeline.renderState')

    local function compare(node, keys, vectors, edits)
        local expected, actual, context = {}, {}, { epoch = 0 }

        local function sample()
            context.epoch = context.epoch + 1
            local a = Reference.fields(expected, node, keys, vectors)
            local b = Properties.fields(actual, node, keys, vectors, context)
            assert(a == b, 'Snapshot change flags differ')
            for _, list in ipairs({ keys, vectors or {} }) do
                for _, key in ipairs(list) do
                    local av, bv = expected[key], actual[key]
                    if type(av) == 'table' then
                        assert(type(bv) == 'table' and #av == #bv, 'Vector sizes differ')
                        for i = 1, #av do
                            assert(av[i] == bv[i], 'Vector components differ')
                        end
                    else
                        assert(av == bv, 'Scalar snapshots differ: ' .. key)
                    end
                end
            end
        end
        sample()
        sample()
        for _, edit in ipairs(edits or {}) do
            edit()
            sample()
            sample()
        end
    end
    local cube = w.byName['Cube10.2']
    compare(cube, State.nodeKeys, State.nodeVectors)
    compare(cube, State.meshKeys, State.meshVectors)
    compare(w.lights[1], State.lightKeys, State.lightVectors)
    compare(c, State.cameraKeys)
    local surface = cube.children[1]
    assert(surface:isA('SurfaceAppearance3D'))
    compare(surface, State.surfaceKeys, State.surfaceVectors)
    test:check(true, 'Render schemas match the reference for meshes, surfaces, lights and cameras')
    compare(cube, { '_probeScalar' }, nil, {
        function()
            cube._probeScalar = false
        end,
        function()
            cube._probeScalar = 0
        end,
        function()
            cube._probeScalar = nil
        end,
    })
    test:check(true, 'False, zero and nil scalar changes retain reference semantics')
    compare(cube, {}, { '_probeVector' }, {
        function()
            cube._probeVector = { 1, 2, 3 }
        end,
        function()
            cube._probeVector[2] = 7
        end,
        function()
            cube._probeVector = { 1, 7 }
        end,
        function()
            cube._probeVector = { 1, 7, 3, 4 }
        end,
        function()
            cube._probeVector = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
        end,
        function()
            cube._probeVector[16] = 20
        end,
        function()
            cube._probeVector = nil
        end,
    })
    test:check(true, 'Mutable, replaced, resized and removed vectors retain reference semantics')
    local offset = { surface.textureOffset[1], surface.textureOffset[2] }
    compare(surface, {}, { 'textureOffset' }, {
        function()
            surface.textureOffset[1] = 7
        end,
        function()
            surface.textureOffset = { 8, 9 }
        end,
        function()
            surface.textureOffset = offset
        end,
    })
    test:check(true, 'Typed vectors retain in-place and whole-value editing')
    local class = cube._class
    compare(cube, { '_probeDefault' }, { '_probeDefaultVector' }, {
        function()
            class._probeDefault = false
            class._probeDefaultVector = { 1, 2, 3 }
        end,
        function()
            class._probeDefault = true
            class._probeDefaultVector[3] = 5
        end,
        function()
            class._probeDefault = nil
            class._probeDefaultVector = nil
        end,
    })
    test:check(true, 'Shared class defaults and mutable default vectors refresh each inspection')
    local enabled, getter = rawget(cube, 'enabled'), rawget(class, 'getEnabled')
    rawset(cube, 'enabled', nil)
    compare(cube, { 'enabled' }, nil, {
        function()
            class.getEnabled = function(node)
                return not node._probeMuted
            end
        end,
        function()
            cube._probeMuted = true
        end,
        function()
            rawset(class, 'getEnabled', getter)
            cube._probeMuted = nil
        end,
    })
    rawset(cube, 'enabled', enabled)
    test:check(true, 'Inherited enabled getter changes preserve reference behavior')
    local Cache = require('source.engine.graphics.pipeline.frameCache')
    local sibling = w.objects[2] == cube and w.objects[3] or w.objects[2]
    local oldParent, oldSiblingParent = cube.parent, sibling.parent
    local parent = w:create('Node3D', { name = 'SnapshotParent' })
    cube.parent = parent
    sibling.parent = parent
    for i = 1, 3 do
        r:draw(w, c, 1, true)
    end
    local yaw = parent.rotation[2]
    parent.rotation[2] = yaw + 10
    local deps = Cache.inspect(r, w, c, 2, true)
    local affected = 0
    for _, mesh in ipairs(w.objects) do
        if mesh.parent == parent then
            assert(deps.nodes[mesh].chainChanged, 'Shared parent change was missed')
            affected = affected + 1
        end
    end
    assert(affected > 1)
    test:check(true, 'Cached ancestor checks invalidate all siblings when a shared parent moves')
    parent.rotation[2] = yaw
    cube.parent = oldParent
    sibling.parent = oldSiblingParent
    parent:destroy()
    r:draw(w, c, 3, true)
    r:draw(w, c, 3, true)
    cube.rotation[2] = cube.rotation[2] + 5
    r:draw(w, c, 3, true)
    test:check(r.stats.updatedMeshes == 1, 'One animated cube still refreshes exactly one mesh')
    test:check(
        r.stats.cacheCheckPhases.objects >= 0 and r.stats.cacheCheckPhases.lights >= 0,
        'Stats publish separate mesh and light dependency-check timings'
    )
end

function T.new(manager)
    local base = require('source.tests.versions.v85.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v86 regression/integration checks')
    end
    return base
end

return T
