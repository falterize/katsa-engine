-- A moving target invalidates only its own result; changed coverage invalidates all.
local Cache = {}

function Cache.get(state, object, polygons)
    if object.skin or object._resolvedMaterial or object._shaderBoundsUnknown then
        return
    end
    local record = state.visibility and state.visibility[object]
    if
        not record
        or record.camera ~= state.cameraRevision
        or record.polygons ~= polygons
        or record.revision ~= object._batchRevision
        or record.geometry ~= object.geometry
        or record.geometryRevision ~= object.geometry.revision
        or record.boundsRevision ~= object.geometry.boundsRevision
    then
        return
    end
    local first, length = object.geometry.mesh:getDrawRange()
    if
        record.source ~= object.geometry.mesh
        or first ~= record.first
        or length ~= record.length
    then
        return
    end
    if record.mesh then
        local entry = state.records[object]
        if not entry or entry.retired or entry.mesh ~= record.mesh then
            return
        end
        entry.epoch = state.maskEpoch
    end
    return record
end

function Cache.save(state, object, polygons, hidden, mesh, triangles)
    state.visibility = state.visibility or setmetatable({}, { __mode = 'k' })
    local record = state.visibility[object] or {}
    state.visibility[object] = record
    record.camera, record.polygons, record.revision =
        state.cameraRevision, polygons, object._batchRevision
    record.geometry, record.geometryRevision, record.boundsRevision =
        object.geometry, object.geometry.revision, object.geometry.boundsRevision
    record.source = object.geometry.mesh
    record.first, record.length = object.geometry.mesh:getDrawRange()
    record.hidden, record.mesh, record.triangles = hidden, mesh, triangles
end

return Cache
