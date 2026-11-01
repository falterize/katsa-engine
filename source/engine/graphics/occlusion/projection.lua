local ipairs = require('source.engine.math.array').ipairs
-- Current-frame convex coverage. No previous-frame visibility or depth readback.
local Math = require('source.engine.math.math3d')
local Bounds = require('source.engine.graphics.geometry.objectBounds')
local Coverage = require('source.engine.graphics.occlusion.coverage')

local Projection = {}
local cameraFields = { 'width', 'height', 'focal', 'near', 'far' }

function Projection.begin(state, camera)
    state.boundsEpoch = (state.boundsEpoch or 0) + 1
    local values = state.camera or {}
    local changed = false
    for i = 1, 16 do
        if values[i] ~= camera.view[i] then
            changed = true
            values[i] = camera.view[i]
        end
    end
    for _, key in ipairs(cameraFields) do
        if values[key] ~= camera[key] then
            changed = true
            values[key] = camera[key]
        end
    end
    state.camera = values
    if changed then
        state.cameraRevision = (state.cameraRevision or 0) + 1
    end
    state.bounds = state.bounds or setmetatable({}, { __mode = 'k' })
end

function Projection.bounds(object, camera, out, state)
    if
        object.skin
        or object._resolvedMaterial
        or object._shaderBoundsUnknown
        or not object.geometry
        or not object.geometry.vertices
    then
        return
    end
    out = out or {}
    local bounds = Bounds.get(object)
    local record = state and state.bounds[object]
    if state then
        local changed = not record or record.cameraRevision ~= state.cameraRevision
        record = record or { bounds = {}, rect = {} }
        for i = 1, 6 do
            if record.bounds[i] ~= bounds[i] then
                changed = true
                record.bounds[i] = bounds[i]
            end
        end
        state.bounds[object] = record
        record.queryEpoch = state.boundsEpoch
        if not changed then
            if not record.valid then
                return
            end
            for i = 1, 5 do
                out[i] = record.rect[i]
            end
            return out
        end
        record.cameraRevision, record.valid = state.cameraRevision, false
    end
    local minX, minY, minZ, maxX, maxY = math.huge, math.huge, math.huge, -math.huge, -math.huge
    -- AABB corners share each axis product. Keep the original sum order while
    -- avoiding eight function calls and repeated matrix/component reads.
    local m = camera.view
    local ax0, ax1, bx0, bx1, cx0, cx1 =
        m[1] * bounds[1],
        m[1] * bounds[4],
        m[5] * bounds[1],
        m[5] * bounds[4],
        m[9] * bounds[1],
        m[9] * bounds[4]
    local ay0, ay1, by0, by1, cy0, cy1 =
        m[2] * bounds[2],
        m[2] * bounds[5],
        m[6] * bounds[2],
        m[6] * bounds[5],
        m[10] * bounds[2],
        m[10] * bounds[5]
    local az0, az1, bz0, bz1, cz0, cz1 =
        m[3] * bounds[3],
        m[3] * bounds[6],
        m[7] * bounds[3],
        m[7] * bounds[6],
        m[11] * bounds[3],
        m[11] * bounds[6]
    local tx, ty, tz = m[4], m[8], m[12]
    local halfWidth, halfHeight, focal, near =
        camera.width / 2, camera.height / 2, camera.focal, camera.near
    for x = 0, 1 do
        local ax, bx, cx = x == 0 and ax0 or ax1, x == 0 and bx0 or bx1, x == 0 and cx0 or cx1
        for y = 0, 1 do
            local axy, bxy, cxy =
                ax + (y == 0 and ay0 or ay1),
                bx + (y == 0 and by0 or by1),
                cx + (y == 0 and cy0 or cy1)
            for z = 0, 1 do
                local a, b, c =
                    axy + (z == 0 and az0 or az1) + tx,
                    bxy + (z == 0 and bz0 or bz1) + ty,
                    cxy + (z == 0 and cz0 or cz1) + tz
                if c <= near then
                    return
                end
                a, b = halfWidth + a * focal / c, halfHeight - b * focal / c
                minX, minY, minZ, maxX, maxY =
                    math.min(minX, a),
                    math.min(minY, b),
                    math.min(minZ, c),
                    math.max(maxX, a),
                    math.max(maxY, b)
            end
        end
    end
    out[1], out[2], out[3], out[4], out[5] = minX, minY, maxX, maxY, minZ
    if record then
        record.valid = true
        for i = 1, 5 do
            record.rect[i] = out[i]
        end
    end
    return out
end

function Projection.vertexCoordinates(x, y, z, matrix, camera, out)
    x, y, z = Math.transform(matrix, x, y, z)
    if z <= camera.near or z >= camera.far then
        return
    end
    out = out or {}
    out[1], out[2], out[3] =
        camera.width / 2 + x * camera.focal / z, camera.height / 2 - y * camera.focal / z, z
    return out
end

function Projection.vertex(vertex, matrix, camera, out)
    return Projection.vertexCoordinates(vertex[1], vertex[2], vertex[3], matrix, camera, out)
end

function Projection.area(a, b, c)
    return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
end

function Projection.covered(rect, polygon)
    return Coverage.single(
        { rect[1], rect[2], rect[3], rect[2], rect[3], rect[4], rect[1], rect[4] },
        rect[5],
        polygon
    )
end

return Projection
