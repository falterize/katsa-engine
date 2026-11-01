local ipairs = require('source.engine.math.array').ipairs
-- Only actual opaque triangles form occluders; an object's AABB never fills holes.
local Math = require('source.engine.math.math3d')
local Projection = require('source.engine.graphics.occlusion.projection')
local Coverage = require('source.engine.graphics.occlusion.coverage')
local Opacity = require('source.engine.materials.opacity')
local GeometryCache = require('source.engine.graphics.occlusion.geometryCache')

local Occluders = {}

local function largerFirst(a, b)
    if a.area == b.area then
        return a.order < b.order
    end
    return a.area > b.area
end

local function same(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function quad(first, second)
    local common, uniqueA, uniqueB = {}, nil, nil
    for _, a in ipairs(first) do
        local shared = false
        for _, b in ipairs(second) do
            if same(a, b) then
                shared = true
                break
            end
        end
        if shared then
            common[#common + 1] = a
        else
            uniqueA = a
        end
    end
    for _, b in ipairs(second) do
        local shared = false
        for _, a in ipairs(first) do
            if same(a, b) then
                shared = true
                break
            end
        end
        if not shared then
            uniqueB = b
        end
    end
    if #common ~= 2 or not uniqueA or not uniqueB then
        return
    end
    local p = { uniqueA, common[1], uniqueB, common[2] }
    local sign = Projection.area(p[1], p[2], p[3])
    if math.abs(sign) < 0.00001 then
        return
    end
    for i = 2, 4 do
        if Projection.area(p[i], p[i % 4 + 1], p[(i + 1) % 4 + 1]) * sign <= 0 then
            return
        end
    end
    return p
end

local function eligible(object)
    return object:isA('Mesh3D')
        and object.geometry
        and not object.skin
        and not object._resolvedMaterial
        and not object._shaderBoundsUnknown
        and not object.onTop
        and Opacity.object(object)
end

function Occluders.collect(objects, camera, settings, state)
    local candidates = state.candidates or {}
    state.candidates = candidates
    local count = 0
    local rect = state.candidateRect or {}
    state.candidateRect = rect
    for _, object in ipairs(objects) do
        if eligible(object) then
            local projected = Projection.bounds(object, camera, rect, state)
            if projected then
                local area = (rect[3] - rect[1]) * (rect[4] - rect[2])
                if area >= settings.occlusionMinArea then
                    count = count + 1
                    local candidate = candidates[count] or {}
                    candidate.object, candidate.area, candidate.order = object, area, count
                    candidates[count] = candidate
                end
            end
        end
    end
    for i = #candidates, count + 1, -1 do
        candidates[i] = nil
    end
    table.sort(candidates, largerFirst)
    if GeometryCache.reusable(state, candidates, settings) then
        state.polygons = state.geometryCache.polygons
        state.geometryReused = true
        return state.polygons, 0
    end
    state.geometryReused = false
    local polygons, work, used = {}, 0, 0
    local matrix = state.matrix or Math.identity()
    state.matrix = matrix
    for _, entry in ipairs(candidates) do
        if
            #polygons >= settings.occlusionMaxOccluders
            or work >= settings.occlusionTriangleBudget
        then
            break
        end
        used = used + 1
        local object = entry.object
        local mesh = object.geometry.mesh
        local format = mesh:getVertexFormat()
        local supported = format[1][1] == 'VertexPosition'
            and format[1][2] == 'float'
            and format[1][3] == 3
        for _, attribute in ipairs(format) do
            if attribute[1] == 'VertexColor' then
                supported = false
            end
        end
        if supported and mesh:getDrawMode() == 'triangles' then
            Math.multiply(camera.view, object.combined or object.matrix, matrix)
            local map = mesh:getVertexMap()
            local first, length = mesh:getDrawRange()
            first = first or 1
            length =
                math.min(length or math.huge, (map and #map or mesh:getVertexCount()) - first + 1)
            local pending
            for i = first, first + length - 3, 3 do
                if
                    work >= settings.occlusionTriangleBudget
                    or #polygons >= settings.occlusionMaxOccluders
                then
                    break
                end
                work = work + 1
                local tri = {}
                for j = 0, 2 do
                    local x, y, z = mesh:getVertex(map and map[i + j] or i + j)
                    tri[j + 1] = Projection.vertexCoordinates(x, y, z, matrix, camera)
                end
                if tri[1] and tri[2] and tri[3] then
                    local area = Projection.area(tri[1], tri[2], tri[3])
                    if math.abs(area) > 0.00001 and (object.doubleSided or area > 0) then
                        local combined = pending and quad(pending, tri)
                        if combined then
                            polygons[#polygons] = combined
                            combined.object = object
                            combined.sign = Projection.area(combined[1], combined[2], combined[3])
                                        > 0
                                    and 1
                                or -1
                            combined.depth = math.max(
                                combined[1][3],
                                combined[2][3],
                                combined[3][3],
                                combined[4][3]
                            )
                            pending = nil
                        else
                            tri.object, tri.sign, tri.depth =
                                object,
                                area > 0 and 1 or -1,
                                math.max(tri[1][3], tri[2][3], tri[3][3])
                            polygons[#polygons + 1] = tri
                            pending = tri
                        end
                    else
                        pending = nil
                    end
                else
                    pending = nil
                end
            end
        end
    end
    for _, polygon in ipairs(polygons) do
        Coverage.describe(polygon)
    end
    GeometryCache.save(
        state,
        candidates,
        used,
        settings,
        #polygons >= settings.occlusionMaxOccluders or work >= settings.occlusionTriangleBudget,
        polygons
    )
    state.polygons = polygons
    return polygons, work
end

return Occluders
