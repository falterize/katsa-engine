-- Blend shape weights of a Mesh3D as inspector rows: one number per shape, written through the
-- state's proxy table (so every draw of the glTF mesh follows).
local BlendShapeRows = {}

function BlendShapeRows.append(target, result)
    local state = target.blendShapes
    if not state or not target.getBlendShapeCount then
        return
    end
    for index, name in ipairs(state.names) do
        result[#result + 1] = {
            key = 'blend: ' .. name,
            storageKey = index,
            kind = 'number',
            value = state.values[index],
            container = state.proxy,
            hint = 'Blend shape weight, usually 0..1 (Blender Shape Key value).',
        }
    end
end

return BlendShapeRows
