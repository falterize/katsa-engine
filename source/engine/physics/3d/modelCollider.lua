local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Bake immutable render geometry into the local frame of a physical body.
local M = require('../../math.math3d')
local A = require('../../math.affine')
local Decomposition = require('./decomposition')
local Hull = require('./decomposition.hull')
local Level = require('./collisionLevel')

local Builder = {}

function Builder.collect(node, body)
    local source = node.geometrySource
    if node._geometrySourceCache ~= source then
        node._geometryStates = nil
        node._geometryOrder = nil
        node._geometrySourceCache = source
    end
    if type(source) == 'string' then
        return require('source.engine.physics.3d.modelSource').collect(node, source, body)
    end
    assert(
        source and source.isA and source:isA('Node3D') and not source.destroyed,
        'GeometrySource must be a model path or a live Node3D / Mesh3D'
    )
    assert(
        (source._world or source._sceneWorld) == body._world,
        'Collider geometry must belong to the same world'
    )
    node._geometryInverse = A.inverse(body:getWorldMatrix(), node._geometryInverse)
    local inverse = node._geometryInverse
    local parts = {}
    local states = node._geometryStates or {}
    node._geometryStates = states
    local changed = false
    local order = node._geometryOrder or {}
    node._geometryEpoch = (node._geometryEpoch or 0) + 1
    local epoch = node._geometryEpoch

    local function visit(item)
        if item:isA('Mesh3D') then
            local state = states[item] or { snapshot = {} }
            states[item] = state
            state.epoch = epoch
            local frame = M.multiply(inverse, item:getWorldMatrix(), state.scratch)
            state.scratch = frame
            for row = 0, 2 do
                for col = 1, 3 do
                    frame[row * 4 + col] = frame[row * 4 + col] * item.size[col]
                end
            end
            if item.localMatrix then
                frame = M.multiply(frame, item.localMatrix, state.combined)
                state.combined = frame
            end
            for i, v in ipairs(frame) do
                local rounded = math.floor(v * 100000 + 0.5) / 100000
                if state.snapshot[i] ~= rounded then
                    changed = true
                    state.snapshot[i] = rounded
                end
            end
            if
                state.geometry ~= item.geometry
                or state.revision ~= (item.geometry.boundsRevision or 0)
            then
                changed = true
            end
            state.geometry = item.geometry
            state.revision = item.geometry.boundsRevision or 0
            parts[#parts + 1] = { geometry = item.geometry, frame = frame }
            if order[#parts] ~= item then
                changed = true
                order[#parts] = item
            end
        end
        for _, child in ipairs(item.children) do
            visit(child)
        end
    end
    visit(source)
    if #order ~= #parts then
        changed = true
        for i = #order, #parts + 1, -1 do
            order[i] = nil
        end
    end
    for item, state in pairs(states) do
        if item.destroyed or state.epoch ~= epoch then
            states[item] = nil
        end
    end
    node._geometryOrder = order
    if changed then
        node._geometryRevision = (node._geometryRevision or 0) + 1
    end
    assert(#parts > 0, 'GeometrySource contains no Mesh3D geometry')
    return parts, tostring(node._geometryRevision)
end

-- Level names of the physics layer for the kinds it builds.
local PHYSICS_LEVEL = { box = 'Bounding Box', convex = 'Single Convex', trimesh = 'Trimesh' }

-- A flat or one-sided mesh has no volume; a hull needs some thickness.
local function thickened(vertices)
    local kind = Hull.classify(vertices)
    if kind == 'solid' then
        return vertices
    end
    assert(kind ~= 'point', 'Convex collider requires distinct points')
    local solid = Hull.thicken(vertices, 0.03)
    assert(solid, 'Convex collider points are collinear')
    return solid
end

-- Vertices of every part baked into the body's local frame, as render-style triangle lists.
local function bake(node, parts)
    local baked, triangles = {}, 0
    for _, part in ipairs(parts) do
        local vertices = {}
        for i, v in ipairs(part.geometry.vertices) do
            vertices[i] = { M.transform(part.frame, v[1], v[2], v[3]) }
        end
        triangles = triangles + #vertices / 3
        assert(
            triangles <= node.maxTriangles,
            'Collider geometry exceeds MaxTriangles; select a simpler source or raise the '
                .. 'explicit limit'
        )
        baked[#baked + 1] = vertices
    end
    return baked
end

-- One collision shape for the whole source, as in Godot: a model with several meshes gets one
-- hull / one box / one set of pieces, not one per mesh. (Select a part, or give each part its own
-- Collider3D, for per-part shapes.)
function Builder.build(node, body, parts)
    local Physics = require('source.engine.physics')
    local kind = Level.kind(node.collisionLevel)
    assert(
        kind ~= 'trimesh' or body.bodyType == 'Static',
        'Trimesh model collision requires a Static Body3D'
    )
    local soup = {}
    for _, vertices in ipairs(bake(node, parts)) do
        for _, v in ipairs(vertices) do
            soup[#soup + 1] = v
        end
    end
    local descriptor
    if kind == 'multiple' then
        local children = {}
        for _, hull in ipairs(Decomposition.decompose(soup, {
            maxHulls = node.maxHulls,
            hullPoints = node.hullPoints,
            concavity = node.concavity,
            resolution = node.resolution,
        })) do
            children[#children + 1] = { shape = 'Convex', vertices = hull }
        end
        descriptor = { shape = 'Compound', children = children }
    elseif kind == 'simplified' then
        local hull = Decomposition.simplify(soup, node.hullPoints)
        assert(hull, 'Convex collider requires distinct points')
        descriptor = { shape = 'Convex', vertices = hull }
    else
        if kind == 'convex' then
            soup = thickened(soup)
        end
        descriptor = Physics.modelCollider(
            { geometry = { vertices = soup }, size = { 1, 1, 1 } },
            PHYSICS_LEVEL[kind]
        )
    end
    -- Always a compound, so the body treats every level alike.
    local children = descriptor.shape == 'Compound' and descriptor.children or { descriptor }
    return {
        shape = 'Compound',
        children = children,
        position = { unpack(node.position) },
        rotation = { unpack(node.rotation) },
    }
end

return Builder
