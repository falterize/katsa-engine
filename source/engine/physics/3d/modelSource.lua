local Models = require('../../import.models')
local M = require('../../math.math3d')

local Source = {}
local unitScale = { 1, 1, 1 }
local origin = { 0, 0, 0 }

function Source.path(source, resources)
    assert(type(source) == 'string' and source ~= '', 'Enter a model path')
    local path = resources:canonical(source)
    assert(Models.supports(path), 'Collider models support OBJ, GLB and glTF')
    assert(katsa.filesystem.getInfo(path, 'file'), 'Missing collider model: ' .. source)
    return path
end

function Source.collect(holder, source, body)
    local resources = assert(body._world.resources, 'Collider models require world resources')
    if holder._modelSource ~= source or holder._modelResources ~= resources then
        holder._modelSource, holder._modelResources = source, resources
        holder._modelParts, holder._modelScaleSnapshot = nil, nil
        -- Cache failures too: a bad authoring path must not trigger disk I/O every frame.
        local ok, result = pcall(function()
            return Models.load(Source.path(source, resources), resources)
        end)
        holder._model, holder._modelError = ok and result or nil, not ok and tostring(result) or nil
    end
    assert(not holder._modelError, holder._modelError)
    local model = holder._model
    local scale = holder.size or unitScale
    holder._modelScaleSnapshot = holder._modelScaleSnapshot or {}
    local snapshot = holder._modelScaleSnapshot
    local changed = snapshot[1] ~= scale[1] or snapshot[2] ~= scale[2] or snapshot[3] ~= scale[3]
    snapshot[1], snapshot[2], snapshot[3] = scale[1], scale[2], scale[3]
    if not holder._modelParts or changed then
        local parts = {}
        local transform = M.compose(origin, origin, scale)
        for _, part in ipairs(model.parts) do
            -- File geometry is authored in the body's local frame. Keep glTF node
            -- transforms, but never instantiate render nodes or start animation.
            local localMatrix = part.node and part.node.world or part.localMatrix
            parts[#parts + 1] = {
                geometry = part.geometry,
                frame = localMatrix and M.multiply(transform, localMatrix) or transform,
            }
        end
        assert(#parts > 0, 'Collider model contains no geometry')
        holder._modelParts = parts
    end
    return holder._modelParts, source
end

return Source
