local ipairs = require('source.engine.math.array').ipairs
-- Conservative overlap of a light face and the camera's shadow-receiver frustum.
-- Off-screen blockers remain in drawFace: they can shadow visible receivers.
local Receivers = {}

function Receivers.prepare(camera, distance, out, normalBias)
    normalBias = normalBias or 0
    if not camera.forward or not camera.right or not camera.up or not camera.focal then
        return nil, false
    end
    local near = camera.near - normalBias
    local far = math.min(camera.far, distance) + normalBias
    if far <= near then
        return {}, true
    end
    out = out or {}
    local p = camera.worldPosition or camera.position
    local orthographic = camera.orthographic == true
    local scale = orthographic and camera.pixelsPerUnit or camera.focal
    local hx, hy = camera.width / (2 * scale), camera.height / (2 * scale)
    local index = 0
    local changed = false
    for depth = 1, 2 do
        local z = depth == 1 and near or far
        for x = -1, 1, 2 do
            for y = -1, 1, 2 do
                index = index + 1
                local corner = out[index] or {}
                out[index] = corner
                -- Perspective extents grow with depth; orthographic extents stay constant.
                local spreadX = orthographic and hx + normalBias or (z + normalBias) * hx + normalBias
                local spreadY = orthographic and hy + normalBias or (z + normalBias) * hy + normalBias
                for i = 1, 3 do
                    local value = p[i]
                        + camera.forward[i] * z
                        + camera.right[i] * spreadX * x
                        + camera.up[i] * spreadY * y
                    changed = changed or value ~= corner[i]
                    corner[i] = value
                end
            end
        end
    end
    return out, changed
end

function Receivers.overlaps(matrix, corners)
    if corners == nil then
        return true
    end
    if #corners == 0 then
        return false
    end
    for axis = 1, 3 do
        for side = 0, 1 do
            local row, sign = (axis - 1) * 4, side == 0 and 1 or -1
            local a, b, c, d =
                matrix[13] + sign * matrix[row + 1],
                matrix[14] + sign * matrix[row + 2],
                matrix[15] + sign * matrix[row + 3],
                matrix[16] + sign * matrix[row + 4]
            local outside = true
            for _, p in ipairs(corners) do
                if a * p[1] + b * p[2] + c * p[3] + d >= -1e-6 then
                    outside = false
                    break
                end
            end
            if outside then
                return false
            end
        end
    end
    return true
end

function Receivers.collect(objects, camera, distance, out, normalBias)
    distance = distance + (normalBias or 0)
    if not objects then
        return nil, false
    end
    local Bounds = require('source.engine.graphics.geometry.objectBounds')
    out = out or {}
    local count, changed = 0, false
    local p = camera.worldPosition or camera.position
    for _, object in ipairs(objects) do
        if
            object.receiveShadow ~= false
            and (object._renderOpacity or object:getEffectiveOpacity()) > 0
            and not object.onTop
        then
            local bounds = Bounds.get(object)
            local unknown = object._shaderBoundsUnknown == true or object.skin ~= nil
            local padding = object._shaderBoundsPadding or 0
            if unknown or Bounds.distanceSquared(bounds, p) <= (distance + padding) ^ 2 then
                count = count + 1
                local entry = out[count] or {}
                out[count] = entry
                changed = changed or entry.object ~= object
                entry.object = object
                for i = 1, 3 do
                    -- Only the part inside the shadow-distance bounding cube can
                    -- receive a shadow. The cube conservatively contains the sphere.
                    local low = unknown and bounds[i]
                        or math.max(bounds[i] - padding, p[i] - distance)
                    local high = unknown and bounds[i + 3]
                        or math.min(bounds[i + 3] + padding, p[i] + distance)
                    changed = changed or entry[i] ~= low or entry[i + 3] ~= high
                    entry[i], entry[i + 3] = low, high
                end
                changed = changed or entry.conservative ~= unknown
                -- Arbitrary animated vertex code has unknown receiver coverage.
                entry.conservative = unknown
            end
        end
    end
    for i = #out, count + 1, -1 do
        out[i] = nil
        changed = true
    end
    return out, changed
end
-- Reuse receiver clipping only with complete mesh snapshots and identical camera/input lists.
function Receivers.cachedCollect(owner, objects, camera, settings, world)
    local deps = owner.dependencies
    local eligible = objects
        and deps
        and deps.meshSnapshots
        and (not deps.volatile or deps.meshesStable)
        and #(world.decals or {}) == 0
        and not (world.particles and #world.particles.emitters > 0)
    local cached = owner.receiverCache
    local reused = eligible
        and cached
        and cached.world == world
        and cached.revision == deps.casterRevision
        and cached.distance == settings.distance
        and cached.bias == settings.normalBias
        and #cached.objects == #objects
    if reused then
        for i = 1, 16 do
            if cached.matrix[i] ~= camera.viewProjection[i] then
                reused = false
                break
            end
        end
    end
    if reused then
        for i, object in ipairs(objects) do
            if cached.objects[i] ~= object then
                reused = false
                break
            end
        end
    end
    owner.receiversReused = reused == true
    if reused then
        return owner.receivers, false
    end
    local out, changed =
        Receivers.collect(objects, camera, settings.distance, owner.receivers, settings.normalBias)
    if eligible then
        cached = cached or { objects = {}, matrix = {} }
        owner.receiverCache = cached
        cached.world, cached.revision, cached.distance, cached.bias =
            world, deps.casterRevision, settings.distance, settings.normalBias
        for i = 1, 16 do
            cached.matrix[i] = camera.viewProjection[i]
        end
        for i, object in ipairs(objects) do
            cached.objects[i] = object
        end
        for i = #cached.objects, #objects + 1, -1 do
            cached.objects[i] = nil
        end
    else
        owner.receiverCache = nil
    end
    return out, changed
end

function Receivers.faceNeeded(matrix, list)
    if list == nil then
        return true
    end
    for _, b in ipairs(list) do
        if b.conservative then
            return true
        end
        local rejected = false
        for axis = 1, 3 do
            for side = 0, 1 do
                local row, sign = (axis - 1) * 4, side == 0 and 1 or -1
                local a, c, d, e =
                    matrix[13] + sign * matrix[row + 1],
                    matrix[14] + sign * matrix[row + 2],
                    matrix[15] + sign * matrix[row + 3],
                    matrix[16] + sign * matrix[row + 4]
                local maximum = e
                    + a * (a >= 0 and b[4] or b[1])
                    + c * (c >= 0 and b[5] or b[2])
                    + d * (d >= 0 and b[6] or b[3])
                if maximum < -0.00001 then
                    rejected = true
                    break
                end
            end
            if rejected then
                break
            end
        end
        if not rejected then
            return true
        end
    end
    return false
end

return Receivers
