local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Bake immutable render geometry into the local frame of a physical body.
local M = require('source.engine.math.math3d')
local A = require('source.engine.math.affine')

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

function Builder.build(node, body, parts)
    local Physics = require('source.engine.physics')
    assert(
        node.collisionLevel ~= 'Detailed' or body.bodyType == 'Static',
        'Detailed model collision requires a Static Body3D'
    )
    local children = {}
    local triangles = 0
    for _, part in ipairs(parts) do
        local vertices = {}
        for i, v in ipairs(part.geometry.vertices) do
            vertices[i] = { M.transform(part.frame, v[1], v[2], v[3]) }
        end
        triangles = triangles + #vertices / 3
        assert(
            triangles <= node.maxTriangles,
            'Collider geometry exceeds MaxTriangles; select a simpler source or raise the explicit limit'
        )
        if node.collisionLevel == 'Convex' then
            local a, b = vertices[1], nil
            for i = 2, #vertices do
                local v = vertices[i]
                if (v[1] - a[1]) ^ 2 + (v[2] - a[2]) ^ 2 + (v[3] - a[3]) ^ 2 > 0.0000000001 then
                    b = v
                    break
                end
            end
            assert(b, 'Convex collider requires distinct points')
            local nx, ny, nz, magnitude = 0, 0, 0, 0
            for _, c in ipairs(vertices) do
                nx = (b[2] - a[2]) * (c[3] - a[3]) - (b[3] - a[3]) * (c[2] - a[2])
                ny = (b[3] - a[3]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[3] - a[3])
                nz = (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
                magnitude = math.sqrt(nx * nx + ny * ny + nz * nz)
                if magnitude > 0.000001 then
                    break
                end
            end
            assert(magnitude > 0.000001, 'Convex collider points are collinear')
            nx, ny, nz = nx / magnitude, ny / magnitude, nz / magnitude
            local flat = true
            for _, v in ipairs(vertices) do
                if
                    math.abs((v[1] - a[1]) * nx + (v[2] - a[2]) * ny + (v[3] - a[3]) * nz)
                    > 0.00001
                then
                    flat = false
                    break
                end
            end
            if flat then
                local extruded = {}
                for _, v in ipairs(vertices) do
                    extruded[#extruded + 1] =
                        { v[1] + nx * 0.03, v[2] + ny * 0.03, v[3] + nz * 0.03 }
                    extruded[#extruded + 1] =
                        { v[1] - nx * 0.03, v[2] - ny * 0.03, v[3] - nz * 0.03 }
                end
                vertices = extruded
            end
        end
        local descriptor = Physics.modelCollider(
            { geometry = { vertices = vertices }, size = { 1, 1, 1 } },
            node.collisionLevel
        )
        if descriptor.shape == 'Compound' then
            for _, d in ipairs(descriptor.children) do
                children[#children + 1] = d
            end
        else
            children[#children + 1] = descriptor
        end
    end
    return {
        shape = 'Compound',
        children = children,
        position = { unpack(node.position) },
        rotation = { unpack(node.rotation) },
    }
end

return Builder
