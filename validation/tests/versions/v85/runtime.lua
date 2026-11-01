local T = {}

local function extra(test)
    local scene = test.manager:switch(require('source.game.runtime.game').new, 'combined')
    local w, r, c = scene.world, scene.renderer, scene.camera
    local e = w.environment
    e.render.frameCache = false
    e.shadows.enabled = false
    e.debug.gizmos.enabled = false
    local board = w:create('BillboardUI', {
        name = 'CacheProbe',
        adornee = w.byName['Cube10.2'],
        size = { 0, 200, 0, 50 },
        onTop = true,
        maxDistance = 1000,
    })
    local label = board.ui:text({ text = 'Alpha', size = { 1, 0, 1, 0 } }, board.ui.content)

    local function capture(general)
        r.forceGeneralShader = general == true
        r.shadows.nextUpdate = -1
        r:draw(w, c, 1, true)
        local image = r.canvas:newImageData()
        return image
    end

    local function same(a, b)
        local bytesA, bytesB = a:getString(), b:getString()
        local maximum, changed = 0, 0
        for i = 1, #bytesA do
            local d = math.abs(bytesA:byte(i) - bytesB:byte(i))
            maximum = math.max(maximum, d)
            if d > 0 then
                changed = changed + 1
            end
        end
        a:release()
        b:release()
        return maximum <= 1, maximum, changed
    end
    local a = capture(false)
    a:release()
    a = capture(false)
    a:release()
    a = capture(false)
    a:release()
    test:check(
        r.stats.updatedMeshes == 0 and r._frameCache.meshesStable,
        'Billboard UI preserves prepared data for all 401 unchanged meshes'
    )
    test:check(r.lights.poseUpdates == 0, 'Unchanged light transforms are reused')
    test:check(
        r.depthPrepassActive and r.stats.depthPrepassReused and r.stats.depthPrepassDrawCalls == 0,
        'Unchanged opaque depth is reused while world UI remains live'
    )
    a = capture(false)
    local ok, maximum = same(a, capture(true))
    test:check(ok, 'Optimized and general opaque shading agree within one byte (' .. maximum .. ')')
    label.text = 'Changed'
    a = capture(false)
    a:release()
    test:check(r.stats.updatedMeshes == 0, 'Changing billboard text does not rebuild cube meshes')
    local cube = w.byName['Cube10.2']
    cube.rotation[2] = 30
    a = capture(false)
    a:release()
    test:check(r.stats.updatedMeshes == 1, 'Mesh edits beside UI invalidate only the changed cube')
    a = capture(false)
    a:release()
    test:check(
        r.depthPrepassActive and not r.stats.depthPrepassReused,
        'Changed geometry rebuilds the opaque depth cache'
    )
    local light = w.lights[1]
    light.position[1] = light.position[1] + 5
    a = capture(false)
    a:release()
    test:check(
        r.lights.poseUpdates == 1 and r.stats.depthPrepassReused,
        'Light motion updates its pose without rebuilding opaque depth'
    )
    e.shadows.enabled = true
    e.shadows.resolution = 64
    e.shadows.sourceFadeSeconds = 0
    e.shadows.maxUpdateFaces = 195
    for i, l in ipairs(w.lights) do
        l.castShadow = i == 1
    end
    a = capture(false)
    a:release()
    a = capture(false)
    a:release()
    test:check(
        r.shadows.receiversReused and r.shadows.updatedFaces == 0,
        'Stable receivers and local shadow maps are reused beside UI'
    )
    test:check(
        r.shadows.opaqueShader ~= nil,
        'Opaque shadow casters use geometry-only depth shading'
    )
    -- A native attached color stream must retain its alpha behavior after explicit invalidation.
    local geometry = cube.geometry
    local mesh = geometry.mesh
    local colors = {}
    for i = 1, mesh:getVertexCount() do
        colors[i] = { 1, 1, 1, 0.5 }
    end
    local stream =
        katsa.graphics.newMesh({ { 'VertexColor', 'float', 4 } }, colors, 'points', 'static')
    mesh:attachAttribute('VertexColor', stream, 'pervertex')
    geometry.revision = (geometry.revision or 0) + 1
    r:invalidate()
    a = capture(false)
    a:release()
    test:check(
        not require('source.engine.materials.opaqueMesh').eligible(cube, r),
        'Attached VertexColor alpha retains the full material path'
    )
    e.render.depthPrepass = false
    a = capture(false)
    test:check(same(a, capture(true)), 'Attached color streams match the general shader')
    mesh:detachAttribute('VertexColor')
    stream:release()
    geometry.revision = geometry.revision + 1
    r:invalidate()
    test:check(
        require('source.engine.materials.opaqueMesh').eligible(cube, r),
        'Removing a color stream restores the opaque path after invalidation'
    )
end

function T.new(manager)
    local base = require('validation.tests.versions.v84.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v85 regression/integration checks')
    end
    return base
end

return T
