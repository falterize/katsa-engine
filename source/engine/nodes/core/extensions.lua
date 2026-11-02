-- Node extensions: additions to existing node classes made by plugins (or scenes).
--
--   Extensions.add('Body3D', {
--       plugin = 'pathfinding',
--       properties = { navWalkable = { default = true, hint = '...' } },   -- shown in the editor
--       methods = { navCost = function(self) ... end },                    -- added to the class
--       initialize = function(node) ... end,                               -- runs for each new node
--   })
--
-- The class itself is global, so an extension applies to every node of that class created after
-- the plugin was first activated in this process. Adding the same plugin twice is a no-op.
local Extensions = { list = {}, applied = {} }

local function copy(value)
    if type(value) ~= 'table' then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = copy(item)
    end
    return result
end

function Extensions.add(className, spec)
    local Node = require('./baseNode')
    local id = (spec.plugin or '?') .. ':' .. className
    if Extensions.applied[id] then
        return
    end
    Extensions.applied[id] = true
    local class = assert(Node.classes[className], 'Unknown node class to extend: ' .. className)
    local schema = rawget(class, 'propertySchema')
    if not schema then
        schema = {}
        class.propertySchema = schema
    end
    for key, descriptor in pairs(spec.properties or {}) do
        assert(schema[key] == nil and class[key] == nil, 'Extension property exists: ' .. key)
        schema[key] = descriptor
    end
    for name, method in pairs(spec.methods or {}) do
        assert(class[name] == nil, 'Extension method exists: ' .. name)
        class[name] = method
    end
    local entries = Extensions.list[className] or {}
    Extensions.list[className] = entries
    entries[#entries + 1] = spec
end

-- Called by the class initializer chain after `className`'s own initialize.
function Extensions.run(className, instance)
    for _, spec in ipairs(Extensions.list[className] or {}) do
        for key, descriptor in pairs(spec.properties or {}) do
            if rawget(instance, key) == nil and descriptor.default ~= nil then
                instance[key] = copy(descriptor.default)
            end
        end
        if spec.initialize then
            spec.initialize(instance)
        end
    end
end

return Extensions
