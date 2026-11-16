local ipairs = require('../math.array').ipairs

-- The named nodes of an imported model, as the name-based importers (autoCollision, autoLod) read them.
local ModelNodes = {}

-- Blender's ".001" duplicate suffix is ignored.
function ModelNodes.stripCopy(name)
    return (name:gsub('%.%d+$', ''))
end

-- A list of { name = string, instance = node } for every mounted, non-bone node of the model.
function ModelNodes.candidates(model, objects)
    local list = {}
    if model.nodes then
        for _, n in ipairs(model.nodes) do
            if n.instance and not n.isBone then
                list[#list + 1] = { name = n.name, instance = n.instance }
            end
        end
    else
        for i, part in ipairs(model.parts) do
            local object = objects[i]
            if object and part.name then
                list[#list + 1] = { name = part.name, instance = object }
            end
        end
    end
    return list
end

-- True when the node is a Mesh3D or has a Mesh3D child (a glTF node with several primitives).
function ModelNodes.hasMesh(instance)
    if instance:isA('Mesh3D') then
        return true
    end
    for _, child in ipairs(instance.children or {}) do
        if child:isA('Mesh3D') then
            return true
        end
    end
    return false
end

return ModelNodes
