-- Entity definitions shared by Server and Client. A definition describes one kind of
-- replicated object:
--
--   {
--     create = function(context, props, netId) return object end,   -- required, both sides
--     destroy = function(object) end,
--     fields = { 'position:vec2', 'angle:angle', 'hp:u8' },         -- replicated state
--     simulate = function(object, input, dt) end,   -- input-driven step (server and prediction)
--     relevant = function(player, object) return true end,          -- server interest filter
--     clientAuthoritative = false,   -- the authority client sends the state instead of input
--     get = function(object, name) / set = function(object, name, value)   -- optional accessors
--   }
local Types = require('source.engine.net.types')

local Registry = {}
Registry.__index = Registry

function Registry.new()
    return setmetatable({ definitions = {} }, Registry)
end

function Registry:define(kind, definition)
    assert(type(definition.create) == 'function', kind .. ': create is required')
    local fields = {}
    for index, spec in ipairs(definition.fields or {}) do
        local name, typeName = spec:match('^([%w_]+):([%w_]+)$')
        assert(name, kind .. ': field must look like "name:type", got ' .. tostring(spec))
        fields[index] = { name = name, type = Types.get(typeName) }
    end
    definition.parsedFields = fields
    definition.kind = kind
    self.definitions[kind] = definition
    return definition
end

function Registry:get(kind)
    return assert(self.definitions[kind], 'Unknown entity kind: ' .. tostring(kind))
end

function Registry.read(definition, object, name)
    if definition.get then
        return definition.get(object, name)
    end
    return object[name]
end

function Registry.write(definition, object, name, value)
    if definition.set then
        definition.set(object, name, value)
    else
        object[name] = value
    end
end

-- Current replicated state of an object: { [fieldName] = copy }.
function Registry.capture(definition, object)
    local state = {}
    for _, field in ipairs(definition.parsedFields) do
        local value = Registry.read(definition, object, field.name)
        if value ~= nil then
            state[field.name] = field.type.copy(value)
        end
    end
    return state
end

function Registry.apply(definition, object, state)
    for _, field in ipairs(definition.parsedFields) do
        local value = state[field.name]
        if value ~= nil then
            Registry.write(definition, object, field.name, field.type.copy(value))
        end
    end
end

-- Writes every field of `state` (all fields, in definition order).
function Registry.writeState(definition, writer, state)
    for _, field in ipairs(definition.parsedFields) do
        local value = state[field.name]
        writer:bool(value ~= nil)
        if value ~= nil then
            field.type.write(writer, value)
        end
    end
end

function Registry.readState(definition, reader)
    local state = {}
    for _, field in ipairs(definition.parsedFields) do
        if reader:bool() then
            state[field.name] = field.type.read(reader)
        end
    end
    return state
end

function Registry.sameState(definition, a, b)
    for _, field in ipairs(definition.parsedFields) do
        local x, y = a[field.name], b[field.name]
        if (x == nil) ~= (y == nil) or x ~= nil and not field.type.equals(x, y) then
            return false
        end
    end
    return true
end

return Registry
