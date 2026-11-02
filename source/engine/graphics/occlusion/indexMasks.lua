local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Instances with identical visible indices share a draw mesh and remain batchable.
local Masks = {}

function Masks.begin(state)
    state.maskEpoch = (state.maskEpoch or 0) + 1
    state.maskSources = state.maskSources or {}
    state.records = state.records or {}
    state.maskBytes = state.maskBytes or 0
    for object in pairs(state.records) do
        if object.destroyed then
            state.records[object] = nil
        end
    end
    for source, entries in pairs(state.maskSources) do
        for signature, entry in pairs(entries) do
            if entry.epoch < state.maskEpoch - 120 then
                entry.retired = true
                entry.mesh:release()
                state.maskBytes = state.maskBytes - entry.bytes
                entries[signature] = nil
            end
        end
        if next(entries) == nil then
            state.maskSources[source] = nil
        end
    end
end

function Masks.select(state, object, indices)
    local source = object.geometry.mesh
    local entries = state.maskSources[source] or {}
    state.maskSources[source] = entries
    local signature = table.concat(indices, ',')
    local entry = entries[signature]
    if not entry then
        local count = 0
        for _ in pairs(entries) do
            count = count + 1
        end
        local bytes = source:getVertexCount() * 4 + #indices * 4 + #signature
        if count >= 256 or state.maskBytes + bytes > (state.maskByteLimit or 16777216) then
            return
        end -- Retain original geometry when cache capacity is exhausted.
        local mesh = katsa.graphics.newMesh(
            { { 'maskCarrier', 'float', 1 } },
            source:getVertexCount(),
            'triangles',
            'static'
        )
        for _, attribute in ipairs(source:getVertexFormat()) do
            mesh:attachAttribute(attribute[1], source, 'pervertex')
        end
        mesh:setVertexMap(indices)
        entry = { mesh = mesh, source = source, bytes = bytes }
        state.maskBytes = state.maskBytes + bytes
        entries[signature] = entry
    end
    entry.epoch = state.maskEpoch
    state.records[object] = entry
    return entry.mesh
end

function Masks.release(state)
    for _, entries in pairs(state and state.maskSources or {}) do
        for _, entry in pairs(entries) do
            entry.mesh:release()
        end
    end
end

return Masks
