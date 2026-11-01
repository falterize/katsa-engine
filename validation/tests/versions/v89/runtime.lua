local T = {}

local function extra(test)
    local V = require('source.engine.math.vector3')
    local Managed = require('source.engine.math.managedValue')
    local scene = test.manager:switch(require('source.game.runtime.game').new, 'combined')
    local w, r, c = scene.world, scene.renderer, scene.camera
    w.environment.shadows.enabled = false
    w.environment.render.frameCache = false
    local mesh = w.byName['Cube10.2']
    mesh.rotation = { 1, 2, 3 }
    local rev = mesh._propertyRevision
    mesh.rotation.y = 2
    test:check(mesh._propertyRevision == rev, 'Identical component writes do not dirty the owner')
    mesh.rotation[2] = 4
    test:check(
        mesh._propertyRevision == rev + 1,
        'Numeric component writes advance the owning node revision'
    )
    local old = mesh.rotation
    mesh.rotation = { 4, 5, 6 }
    rev = mesh._propertyRevision
    old.X = 20
    test:check(
        mesh._propertyRevision == rev and mesh.rotation.x == 4,
        'Detached vectors no longer dirty or modify their previous owner'
    )
    local copy = mesh.rotation:toArray()
    copy[1] = 100
    test:check(mesh.rotation.x == 4, 'toArray returns an independent ordinary array')
    local v = V.new(1, 2, 3)
    mesh.position = v
    v.Z = 100
    test:check(
        mesh.position.z == 3 and Managed.is(mesh.position),
        'Assigning a vector copies its components'
    )
    local sum = V.new(1, 2, 3) + V.new(3, 2, 1)
    local cross = V.new(1, 0, 0):cross(V.new(0, 1, 0))
    test:check(
        sum.x == 4 and sum.Y == 4 and cross.z == 1 and V.new(3, 0, 0):unit().x == 1,
        'Managed vectors retain arithmetic, cross products and normalization'
    )
    test:check(not pcall(function()
        mesh.rotation.x = 0 / 0
    end) and not pcall(function()
        mesh.rotation[4] = 1
    end), 'Invalid components are rejected before mutating a managed vector')
    local surface = mesh.children[1]
    for _ = 1, 2 do
        r:draw(w, c, 20, true)
    end
    surface.color.r = surface.color.r * 0.5
    r:draw(w, c, 21, true)
    test:check(
        r.stats.updatedMeshes == 1,
        'A color component write invalidates exactly its owning mesh'
    )
    mesh.localMatrix = require('source.engine.math.math3d').identity()
    r:draw(w, c, 22, true)
    mesh.localMatrix[4] = 17
    r:draw(w, c, 23, true)
    test:check(
        r.stats.updatedMeshes == 1,
        'In-place raw matrix edits remain observable beside managed vectors'
    )
    local visible = c._class.visible
    local visibilityCalls = 0
    c._class.visible = function()
        visibilityCalls = visibilityCalls + 1
        return false
    end
    r:draw(w, c, 23.5, true)
    test:check(
        visibilityCalls > 0,
        'Custom camera visibility overrides retain their renderer behavior'
    )
    c._class.visible = visible
    mesh.localMatrix = nil
    r:draw(w, c, 24, true)
    r:draw(w, c, 25, true)
    test:check(r.stats.updatedMeshes == 0, 'Removing a raw matrix restores the stable mesh path')
end

function T.new(manager)
    local base = require('validation.tests.versions.v88.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v89 regression/integration checks')
    end
    return base
end

return T
