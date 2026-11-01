local ipairs = require('source.engine.math.array').ipairs
-- Cached conservative world AABBs; geometric bounds stay independent of scale.
local Bounds = {}

function Bounds.localBounds(geometry)
    local localBounds = geometry.bounds
    if not localBounds or geometry._boundsRevision ~= (geometry.boundsRevision or 0) then
        localBounds = { math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge }
        for _, v in ipairs(geometry.vertices) do
            for i = 1, 3 do
                localBounds[i] = math.min(localBounds[i], v[i])
                localBounds[i + 3] = math.max(localBounds[i + 3], v[i])
            end
        end
        geometry.bounds = localBounds
        geometry._boundsRevision = geometry.boundsRevision or 0
    end
    return localBounds
end

function Bounds.get(object)
    local geometry = object.geometry
    local localBounds = Bounds.localBounds(geometry)
    local cache = object._boundsCache or { matrix = {}, bounds = {} }
    object._boundsCache = cache
    local world = object._world
    local dependencies = world and world._activeRenderer and world._activeRenderer._frameCache
    if
        world
        and world._renderResolving
        and dependencies
        and dependencies.meshSnapshots
        and object._preparedMesh
        and cache.batchRevision == object._batchRevision
        and cache.geometry == geometry
        and cache.boundsRevision == geometry._boundsRevision
        and cache.padding == (object.shadowBoundsPadding or 0)
    then
        return cache.bounds
    end
    local m = object.combined or object.matrix
    cache.batchRevision = object._batchRevision
    local dirty = cache.boundsRevision ~= geometry._boundsRevision
        or cache.geometry ~= geometry
        or cache.padding ~= (object.shadowBoundsPadding or 0)
    for i = 1, 16 do
        if cache.matrix[i] ~= m[i] then
            dirty = true
            cache.matrix[i] = m[i]
        end
    end
    if not dirty then
        return cache.bounds
    end
    cache.geometry, cache.padding = geometry, object.shadowBoundsPadding or 0
    cache.boundsRevision = geometry._boundsRevision
    local b = cache.bounds
    for i = 1, 3 do
        local row = (i - 1) * 4
        local lo, hi = m[row + 4], m[row + 4]
        for j = 1, 3 do
            local a, c = m[row + j] * localBounds[j], m[row + j] * localBounds[j + 3]
            lo, hi = lo + math.min(a, c), hi + math.max(a, c)
        end
        b[i], b[i + 3] = lo - cache.padding, hi + cache.padding
    end
    return b
end

function Bounds.distanceSquared(b, p)
    local sum = 0
    for i = 1, 3 do
        local d = math.max(b[i] - p[i], 0, p[i] - b[i + 3])
        sum = sum + d * d
    end
    return sum
end

return Bounds
