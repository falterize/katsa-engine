local T = {}

local function extra(test)
    local scene = test.manager:switch(require('source.game.runtime.game').new, 'combined')
    local w, r, c = scene.world, scene.renderer, scene.camera
    w.environment.shadows.enabled = false
    w.environment.render.frameCache = false
    local mesh = w.byName['Cube10.2']
    mesh.rotation = { 1, 2, 3 }
    mesh.rotation.y = 12
    mesh.rotation.Z = 13
    test:check(
        mesh.rotation[2] == 12 and mesh.rotation.Y == 12 and mesh.rotation.z == 13,
        '3D transform components support lowercase, uppercase and numeric access'
    )
    mesh.position = { 1, 2, 3 }
    mesh.size = { 10, 11, 12 }
    mesh.scale = { 1, 1, 1 }
    mesh.position.X = 4
    mesh.size.z = 14
    mesh.scale.y = 2
    test:check(
        mesh.position.x == 4 and mesh.size.Z == 14 and mesh.scale[2] == 2,
        'Position, Size and Scale retain named components after whole-value assignment'
    )
    local input = { 4, 5, 6 }
    mesh.rotation = input
    input[2] = 20
    local n, sum = 0, 0
    for _, value in ipairs(mesh.rotation:toArray()) do
        n = n + 1
        sum = sum + value
    end
    local x, y, z = unpack(mesh.rotation:toArray())
    test:check(
        mesh.rotation ~= input
            and #mesh.rotation == 3
            and n == 3
            and sum == 15
            and x == 4
            and y == 5
            and z == 6,
        'Managed transforms copy inputs and provide explicit array iteration/unpack'
    )
    local surface = mesh.children[1]
    surface.textureOffset = { 2, 3 }
    surface.textureOffset.x = 7
    surface.textureOffset.Y = 8
    surface.tileSize = { 0, 32, 0, 32 }
    surface.tileSize.scaleX = 0.5
    surface.tileSize.OffsetY = 40
    test:check(
        surface.textureOffset[1] == 7
            and surface.textureOffset.y == 8
            and surface.tileSize[1] == 0.5
            and surface.tileSize.offsetY == 40,
        'Vector2 and UDim2 support matching lowercase and uppercase component names'
    )
    local before = mesh._propertyRevision
    mesh.visible = false
    local changed = mesh._propertyRevision
    mesh.visible = false
    test:check(
        changed > before and mesh._propertyRevision == changed,
        'Scalar writes advance revisions only when the stored value changes'
    )
    mesh.visible = true
    for i = 1, 3 do
        r:draw(w, c, 1, true)
    end
    test:check(
        r._frameCache.scalarNodesSkipped > 800,
        'Stable mesh, appearance and light scalar schemas skip full comparisons'
    )
    mesh.unlit = not mesh.unlit
    r:draw(w, c, 2, true)
    test:check(
        r.stats.updatedMeshes == 1,
        'A scalar mesh change invalidates exactly its own prepared mesh'
    )
    r:draw(w, c, 2, true)
    surface.roughness = 0.2
    r:draw(w, c, 3, true)
    test:check(r.stats.updatedMeshes == 1, 'A scalar appearance change invalidates its owning mesh')
    r:draw(w, c, 3, true)
    mesh.rotation.y = mesh.rotation.y + 10
    r:draw(w, c, 4, true)
    test:check(
        r.stats.updatedMeshes == 1,
        'A named component edit is visible in the same rendered frame'
    )
    r:draw(w, c, 4, true)
    mesh.rotation[2] = mesh.rotation[2] + 10
    r:draw(w, c, 5, true)
    test:check(
        r.stats.updatedMeshes == 1,
        'Legacy numeric component edits remain visible in the same frame'
    )
    local other = require('source.engine.graphics.pipeline.renderer').new(scene.resources)
    other:draw(w, c, 5, true)
    other:draw(w, c, 5, true)
    mesh.receiveShadow = not mesh.receiveShadow
    r:draw(w, c, 6, true)
    other:draw(w, c, 6, true)
    test:check(
        r.stats.updatedMeshes == 1 and other.stats.updatedMeshes == 1,
        'Independent renderers observe scalar revisions without consuming each other changes'
    )
    other:release()
end

function T.new(manager)
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    local base = require('source.tests.versions.v87.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v88 regression/integration checks')
    end
    return base
end

return T
