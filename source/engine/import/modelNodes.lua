local ipairs = require('../math.array').ipairs

-- The named nodes of an imported model, as the name-based importers (autoCollision, autoLod) read them.
local ModelNodes = {}

-- Blender's ".001" duplicate suffix is ignored.
function ModelNodes.stripCopy(name)
    return (name:gsub('%.%d+$', ''))
end

-- The name suffixes the importers read, in any order: `-colonly` / `-col` (collision, see
-- autoCollision) and `-lodN` (level of detail, see autoLod). `Tree-lod1-col` and `Tree-col-lod1`
-- both mean level 1 of `Tree` with a collider. Each kind counts once; matching is case-insensitive.
-- Returns { base = string, level = number|nil, collision = 'visible'|'only'|nil }, or nil when the
-- name has no suffix.
function ModelNodes.parse(name)
    if type(name) ~= 'string' then
        return nil
    end
    local rest = ModelNodes.stripCopy(name)
    local result = {}
    local found = false
    local progress = true
    while progress do
        progress = false
        local lower = rest:lower()
        local level = lower:match('%-lod(%d+)$')
        if level and result.level == nil and #lower > #level + 4 then
            result.level = tonumber(level)
            rest = rest:sub(1, #rest - #level - 4)
            progress = true
        elseif result.collision == nil and #lower > 8 and lower:sub(-8) == '-colonly' then
            result.collision = 'only'
            rest = rest:sub(1, #rest - 8)
            progress = true
        elseif result.collision == nil and #lower > 4 and lower:sub(-4) == '-col' then
            result.collision = 'visible'
            rest = rest:sub(1, #rest - 4)
            progress = true
        end
        found = found or progress
    end
    if not found then
        return nil
    end
    result.base = rest
    return result
end

-- Records a problem found in a model file in the resource journal (shown in the debug window).
function ModelNodes.warn(world, message)
    local store = world.resources and world.resources.store
    if store and store.journal then
        store.journal:record('Resources', message, nil, message)
    end
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
