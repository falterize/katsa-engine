-- Godot-style collision levels: Simplified / Multiple Convex, legacy names, descriptor shapes.
local Level = require('source.engine.physics.3d.collisionLevel')
local Decomposition = require('source.engine.physics.3d.decomposition')
local ModelCollider = require('source.engine.physics.3d.modelCollider')

local Tests = {}

-- An "L" built from two boxes, as a triangle soup (12 triangles per box).
local function box(soup, x0, y0, z0, x1, y1, z1)
    local c = {}
    for i = 0, 7 do
        c[i] = {
            i % 2 == 0 and x0 or x1,
            math.floor(i / 2) % 2 == 0 and y0 or y1,
            math.floor(i / 4) == 0 and z0 or z1,
        }
    end
    local quads = { { 0, 1, 3, 2 }, { 4, 6, 7, 5 }, { 0, 2, 6, 4 }, { 1, 5, 7, 3 }, { 0, 4, 5, 1 }, { 2, 3, 7, 6 } }
    for _, q in ipairs(quads) do
        for _, n in ipairs({ 1, 2, 3, 1, 3, 4 }) do
            soup[#soup + 1] = c[q[n]]
        end
    end
end

function Tests.run(tester)
    tester:check(Level.kind('Multiple Convex') == 'multiple', 'Multiple Convex level is known')
    tester:check(
        Level.kind('Trimesh') == 'trimesh' and Level.kind('Single Convex') == 'convex'
            and Level.kind('Bounding Box') == 'box',
        'level names map to their kinds'
    )
    tester:check(not pcall(Level.kind, 'Detailed'), 'the removed level names are rejected')

    local soup = {}
    box(soup, 0, 0, 0, 4, 1, 1)
    box(soup, 0, 1, 0, 1, 4, 1)
    local hulls = Decomposition.decompose(soup, { maxHulls = 8 })
    tester:check(#hulls >= 2 and #hulls <= 4, 'an L-shaped model splits into a few hulls')
    local single = Decomposition.decompose(soup, { maxHulls = 1 })
    tester:check(#single == 1, 'maxHulls = 1 gives one hull')

    local World = require('source.engine.world.world')
    local resources = tester.manager.resources:scope()
    local world = World.new(resources)
    world:createPhysics({ backend = 'oimo', gravity = { 0, 0, 0 } })
    local body = world:create('Body3D', { bodyType = 'Dynamic' })
    local collider = world:create('Collider3D', {
        shape = 'Geometry',
        geometrySource = 'shared://models/examples/pyramid.obj',
        collisionLevel = 'Multiple Convex',
    }, body)
    world:updateNodes(1 / 60)
    tester:check(collider.status == 'Ready' and #body.body.shapes >= 1, 'Multiple Convex builds from a file')
    collider.collisionLevel = 'Simplified Convex'
    world:updateNodes(1 / 60)
    tester:check(collider.status == 'Ready' and #body.body.shapes >= 1, 'Simplified Convex builds from a file')
    tester:check(ModelCollider ~= nil, 'model collider module loads')
end

return Tests
