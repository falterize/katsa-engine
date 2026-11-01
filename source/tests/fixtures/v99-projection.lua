local ipairs = require('source.engine.math.array').ipairs
-- Current-frame convex coverage. No previous-frame visibility or depth readback.
local Math = require('source.engine.math.math3d')
local Bounds = require('source.engine.graphics.geometry.objectBounds')
local Coverage = require('source.engine.graphics.occlusion.coverage')
local Projection = {}
local cameraFields = { 'width', 'height', 'focal', 'near', 'far' }
function Projection.begin(state, camera)
    local values = state.camera or {}
    local changed = false
    for i = 1, 16 do
        if values[i] ~= camera.view[i] then changed = true; values[i] = camera.view[i] end
    end
    for _, key in ipairs(cameraFields) do
        if values[key] ~= camera[key] then changed = true; values[key] = camera[key] end
    end
    state.camera = values
    if changed then state.cameraRevision = (state.cameraRevision or 0) + 1 end
    state.bounds = state.bounds or setmetatable({}, { __mode = 'k' })
end
function Projection.bounds(object, camera, out, state)
    if object.skin or object._resolvedMaterial or object._shaderBoundsUnknown
        or not object.geometry or not object.geometry.vertices then return end
    out = out or {}
    local bounds = Bounds.get(object)
    local record = state and state.bounds[object]
    if state then
        local changed = not record or record.cameraRevision ~= state.cameraRevision
        record = record or { bounds = {}, rect = {} }
        for i = 1, 6 do
            if record.bounds[i] ~= bounds[i] then changed = true; record.bounds[i] = bounds[i] end
        end
        state.bounds[object] = record
        if not changed then
            if not record.valid then return end
            for i = 1, 5 do out[i] = record.rect[i] end
            return out
        end
        record.cameraRevision, record.valid = state.cameraRevision, false
    end
    local minX, minY, minZ, maxX, maxY = math.huge, math.huge, math.huge, -math.huge, -math.huge
    for x = 0, 1 do for y = 0, 1 do for z = 0, 1 do
        local a, b, c = Math.transform(camera.view, bounds[1 + x * 3], bounds[2 + y * 3], bounds[3 + z * 3])
        if c <= camera.near then return end
        a, b = camera.width/2 + a * camera.focal/c, camera.height/2-b * camera.focal/c
        minX, minY, minZ, maxX, maxY = math.min(minX, a), math.min(minY, b), math.min(minZ, c), math.max(maxX, a), math.max(maxY, b)
    end end end
    out[1], out[2], out[3], out[4], out[5] = minX, minY, maxX, maxY, minZ
    if record then
        record.valid = true
        for i = 1, 5 do record.rect[i] = out[i] end
    end
    return out
end
function Projection.vertex(vertex, matrix, camera, out)
    local x, y, z = Math.transform(matrix, vertex[1], vertex[2], vertex[3])
    if z <= camera.near or z >= camera.far then return end
    out = out or {}
    out[1], out[2], out[3] = camera.width/2 + x * camera.focal/z, camera.height/2-y * camera.focal/z, z
    return out
end
function Projection.area(a, b, c)
    return (b[1]-a[1]) * (c[2]-a[2])-(b[2]-a[2]) * (c[1]-a[1])
end
function Projection.covered(rect, polygon)
    return Coverage.single({rect[1],rect[2],rect[3],rect[2],rect[3],rect[4],rect[1],rect[4]}, rect[5], polygon)
end
return Projection
