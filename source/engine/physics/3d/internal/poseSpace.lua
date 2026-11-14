local Affine = require('source.engine.math.affine')

local Space = {}
-- Body-owned cache; compare matrix contents to retain support for raw matrix edits.
function Space.parentInverse(body, parent)
    if not parent then
        if body._parentPoseValues then
            body._parentPoseRevision = (body._parentPoseRevision or 0) + 1
        end
        body._parentPoseValues = nil
        body._parentPoseInverse = nil
        return nil
    end
    local values = body._parentPoseValues
    local changed = not values
    if values then
        for i = 1, 16 do
            if values[i] ~= parent[i] then
                changed = true
                break
            end
        end
    end
    if changed then
        local _, _, scale = Affine.decompose(parent)
        for i = 1, 3 do
            assert(
                math.abs(scale[i] - 1) < 1e-6,
                'Body3D parent frame must stay unscaled; use inheritScale=false for scaled supports'
            )
        end
        body._parentPoseInverse = Affine.inverse(parent, body._parentPoseInverse)
        values = values or {}
        body._parentPoseValues = values
        for i = 1, 16 do
            values[i] = parent[i]
        end
        body._parentPoseRevision = (body._parentPoseRevision or 0) + 1
    end
    return body._parentPoseInverse
end
-- A body owns one exact output snapshot. No frame stamps: raw solver edits,
-- authored local edits, parent changes and mutable output matrices remain observable.
function Space.matches(body, world, position, rotation)
    local cache, object = body._syncCache, body.node
    if
        not cache
        or cache.independent ~= object._independentBody
        or cache.parentRevision ~= body._parentPoseRevision
        or cache.matrix ~= object.physicsMatrix
        or object._independentBody and not body._poseSnapshot
    then
        return false
    end
    for i = 1, 12 do
        if cache.world[i] ~= world[i] then
            return false
        end
    end
    for i = 1, 3 do
        if cache.pose[i] ~= position[i] or cache.pose[i + 3] ~= rotation[i] then
            return false
        end
    end
    local matrix = object.physicsMatrix
    for i = 1, 16 do
        if cache.output[i] ~= matrix[i] then
            return false
        end
    end
    return true
end

function Space.capture(body, world, position, rotation)
    local cache = body._syncCache
    if not cache then
        cache = { world = {}, pose = {}, output = {} }
        body._syncCache = cache
    end
    cache.independent, cache.parentRevision = body.node._independentBody, body._parentPoseRevision
    cache.matrix = body.node.physicsMatrix
    for i = 1, 12 do
        cache.world[i] = world[i]
    end
    for i = 1, 3 do
        cache.pose[i], cache.pose[i + 3] = position[i], rotation[i]
    end
    for i = 1, 16 do
        cache.output[i] = cache.matrix[i]
    end
end

return Space
