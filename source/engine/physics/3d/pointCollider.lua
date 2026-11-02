local Array = require('../../math.array')
local M = require('../../math.math3d')
local Geometry = require('./modelCollider')

local PointCollider = {}

function PointCollider.copy(points)
    assert(Array.is(points), 'Expected a table of 3D points')
    local result = {}
    if type(points[1]) == 'number' then
        assert(#points % 3 == 0, 'Flat 3D points require XYZ triples')
        for i = 1, #points, 3 do
            result[#result + 1] = { points[i], points[i + 1], points[i + 2] }
        end
    else
        for _, point in Array.ipairs(points) do
            result[#result + 1] = { point[1], point[2], point[3] }
        end
    end
    assert(#result >= 3, 'A collider requires at least three 3D points')
    for _, point in ipairs(result) do
        for i = 1, 3 do
            local value = point[i]
            assert(
                type(value) == 'number' and value == value and math.abs(value) < math.huge,
                '3D points must contain finite XYZ components'
            )
        end
    end
    return result
end

function PointCollider.extract(source, body, options)
    options = options or {}
    assert(body and body:isA('Body3D'), 'Mesh extraction requires a Body3D coordinate frame')
    local collector = { geometrySource = source, size = options.scale or { 1, 1, 1 } }
    local parts = Geometry.collect(collector, body)
    local points, indices, seen = {}, {}, {}
    local epsilon = options.weldEpsilon or 0.000001
    assert(epsilon > 0 and epsilon < math.huge, 'weldEpsilon must be finite and positive')
    local limit = options.maxTriangles or 4096
    for _, part in ipairs(parts) do
        for _, vertex in Array.ipairs(part.geometry.vertices) do
            local x, y, z = M.transform(part.frame, vertex[1], vertex[2], vertex[3])
            local key = math.floor(x / epsilon + 0.5)
                .. ':'
                .. math.floor(y / epsilon + 0.5)
                .. ':'
                .. math.floor(z / epsilon + 0.5)
            local index = seen[key]
            if not index then
                points[#points + 1] = { x, y, z }
                index, seen[key] = #points, #points
            end
            indices[#indices + 1] = index
            assert(#indices <= limit * 3, 'Mesh extraction exceeds maxTriangles')
        end
    end
    return points, indices
end

function PointCollider.changed(node)
    local inputs, count, changed = node._pointInputs or {}, 0, false
    node._pointInputs = inputs
    local function add(value)
        count = count + 1
        changed = inputs[count] ~= value or changed
        inputs[count] = value
    end
    for _, values in ipairs({ node.points or node.vertices or {}, node.indices or {} }) do
        add(#values)
        for _, value in Array.ipairs(values) do
            if type(value) == 'number' then
                add(value)
            else
                for i = 1, 3 do
                    add(value[i])
                end
            end
        end
    end
    for i = #inputs, count + 1, -1 do
        inputs[i], changed = nil, true
    end
    if changed then
        node._pointRevision = (node._pointRevision or 0) + 1
    end
    return tostring(node._pointRevision or 0)
end

function PointCollider.build(node, body)
    local points = PointCollider.copy(node.points or node.vertices)
    assert(
        node.collisionLevel ~= 'Detailed' or body.bodyType == 'Static',
        'Detailed points require a Static Body3D'
    )
    local triangles = points
    if node.collisionLevel == 'Detailed' and node.indices then
        assert(#node.indices % 3 == 0, 'Triangle indices require triples')
        triangles = {}
        for i, index in Array.ipairs(node.indices) do
            assert(
                type(index) == 'number' and index % 1 == 0 and points[index],
                'Triangle index is outside the point list'
            )
            triangles[i] = points[index]
        end
    end
    if node.collisionLevel == 'Detailed' then
        assert(
            #triangles >= 3 and #triangles % 3 == 0,
            'Detailed points require indexed triangles or a triangle-soup list'
        )
    else
        -- Geometry.build consumes a render-style triangle list; hull points may have
        -- any count. Padding with duplicates preserves the hull and bounding box.
        triangles = {}
        for i, point in ipairs(points) do
            triangles[i] = point
        end
        while #triangles % 3 ~= 0 do
            triangles[#triangles + 1] = points[#points]
        end
    end
    local descriptor = Geometry.build(node, body, {
        { geometry = { vertices = triangles }, frame = M.identity() },
    })
    return descriptor
end

return PointCollider
