local ipairs = require('source.engine.math.array').ipairs
-- Reuse selected coverage geometry only while its actual inputs remain unchanged.
local Cache = {}

local function values(object)
    local geometry, mesh = object.geometry, object.geometry.mesh
    local first, length = mesh:getDrawRange()
    return mesh,
        object._batchRevision,
        geometry.revision,
        geometry.boundsRevision,
        first,
        length,
        mesh:getVertexCount()
end

function Cache.reusable(state, candidates, settings)
    local cache = state.geometryCache
    if
        not cache
        or cache.camera ~= state.cameraRevision
        or cache.limit ~= settings.occlusionMaxOccluders
        or cache.budget ~= settings.occlusionTriangleBudget
        or cache.invalidation ~= (settings.world and settings.world._renderInvalidationRevision or 0)
        or cache.rendererInvalidation ~= (settings._renderInvalidationRevision or 0)
        or #candidates < #cache.inputs
        or (not cache.exhausted and #candidates ~= #cache.inputs)
    then
        return false
    end
    for i, record in ipairs(cache.inputs) do
        local object = candidates[i].object
        if object ~= record.object then
            return false
        end
        local mesh, revision, geometryRevision, boundsRevision, first, length, count =
            values(object)
        if
            mesh ~= record.mesh
            or revision ~= record.revision
            or geometryRevision ~= record.geometryRevision
            or boundsRevision ~= record.boundsRevision
            or first ~= record.first
            or length ~= record.length
            or count ~= record.count
        then
            return false
        end
    end
    return true
end

function Cache.save(state, candidates, used, settings, exhausted, polygons)
    local cache = state.geometryCache or { inputs = {} }
    state.geometryCache = cache
    cache.camera, cache.limit, cache.budget =
        state.cameraRevision, settings.occlusionMaxOccluders, settings.occlusionTriangleBudget
    cache.invalidation = settings.world and settings.world._renderInvalidationRevision or 0
    cache.rendererInvalidation = settings._renderInvalidationRevision or 0
    cache.exhausted, cache.polygons = exhausted, polygons
    for i = 1, used do
        local object = candidates[i].object
        local record = cache.inputs[i] or {}
        cache.inputs[i] = record
        record.object = object
        record.mesh, record.revision, record.geometryRevision, record.boundsRevision, record.first, record.length, record.count =
            values(object)
    end
    for i = #cache.inputs, used + 1, -1 do
        cache.inputs[i] = nil
    end
end

return Cache
