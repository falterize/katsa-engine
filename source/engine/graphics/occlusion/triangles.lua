local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Per-camera index masks share the original vertex buffers, never its index state.
local Math = require('../../math.math3d')
local Coverage = require('./coverage')
local Masks = require('./indexMasks')
local Counts = require('../debug.triangles')

local Triangles = {}

local function supported(object)
    if object.skin or object._resolvedMaterial or object._shaderBoundsUnknown or object.onTop then
        return false
    end
    local mesh = object.geometry and object.geometry.mesh
    if not mesh or mesh:getDrawMode() ~= 'triangles' then
        return false
    end
    local position = mesh:getVertexFormat()[1]
    return position[1] == 'VertexPosition' and position[2] == 'float' and position[3] == 3
end

local function vertex(mesh, index, matrix, camera, cache)
    local offset = index * 3
    if cache[offset] ~= nil then
        return offset
    end
    local x, y, z = mesh:getVertex(index)
    x, y, z = Math.transform(matrix, x, y, z)
    if z <= camera.near or z >= camera.far then
        cache[offset] = false
    else
        cache[offset], cache[offset + 1], cache[offset + 2] =
            camera.width / 2 + x * camera.focal / z, camera.height / 2 - y * camera.focal / z, z
    end
    return offset
end

local function intersects(rect, polygon)
    return rect[1] < polygon.x2
        and rect[3] > polygon.x1
        and rect[2] < polygon.y2
        and rect[4] > polygon.y1
end

function Triangles.filter(object, camera, polygons, rect, state, stats)
    if not supported(object) or state.targetBudget <= 0 then
        return
    end
    -- Whole-object rejection is cheaper than index masks for tiny primitives.
    if Counts.mesh(object.geometry.mesh) <= 24 then
        return
    end
    local candidates = state.targetPolygons or {}
    state.targetPolygons = candidates
    local count = 0
    for _, p in ipairs(polygons) do
        if p.object ~= object and p.depth < rect[5] and intersects(rect, p) then
            count = count + 1
            candidates[count] = p
        end
    end
    for i = #candidates, count + 1, -1 do
        candidates[i] = nil
    end
    if count == 0 then
        return
    end
    local mesh, indices = object.geometry.mesh, state.targetIndices or {}
    state.targetIndices = indices
    for i = #indices, 1, -1 do
        indices[i] = nil
    end
    local map = mesh:getVertexMap()
    local first, length = mesh:getDrawRange()
    first = first or 1
    length = math.min(length or math.huge, (map and #map or mesh:getVertexCount()) - first + 1)
    local cache, matrix = state.targetVertices or {}, state.targetMatrix or Math.identity()
    state.targetVertices = cache
    for key in pairs(cache) do
        cache[key] = nil
    end
    state.targetMatrix = matrix
    Math.multiply(camera.view, object.combined or object.matrix, matrix)
    local removed = 0
    for i = first, first + length - 3, 3 do
        local a, b, c =
            map and map[i] or i, map and map[i + 1] or i + 1, map and map[i + 2] or i + 2
        local hidden = false
        if state.targetBudget > 0 then
            state.targetBudget = state.targetBudget - 1
            stats.occlusionTargetTrianglesTested = stats.occlusionTargetTrianglesTested + 1
            local pa, pb, pc =
                vertex(mesh, a, matrix, camera, cache),
                vertex(mesh, b, matrix, camera, cache),
                vertex(mesh, c, matrix, camera, cache)
            if cache[pa] and cache[pb] and cache[pc] then
                local points = state.trianglePoints or {}
                state.trianglePoints = points
                points[1], points[2], points[3], points[4], points[5], points[6] =
                    cache[pa], cache[pa + 1], cache[pb], cache[pb + 1], cache[pc], cache[pc + 1]
                stats.occlusionTests = stats.occlusionTests + #candidates
                hidden = Coverage.test(
                    points,
                    math.min(cache[pa + 2], cache[pb + 2], cache[pc + 2]),
                    candidates,
                    object,
                    state
                )
            end
        end
        if hidden then
            removed = removed + 1
        else
            indices[#indices + 1], indices[#indices + 2], indices[#indices + 3] = a, b, c
        end
    end
    if removed == 0 then
        return
    end
    if #indices == 0 then
        return false
    end
    local selected = Masks.select(state, object, indices)
    if not selected then
        return
    end
    stats.occlusionPartialTriangles = stats.occlusionPartialTriangles + removed
    stats.occlusionPartialObjects = stats.occlusionPartialObjects + 1
    return selected
end

function Triangles.prune(state)
    Masks.begin(state)
end

function Triangles.release(state)
    Masks.release(state)
end

return Triangles
