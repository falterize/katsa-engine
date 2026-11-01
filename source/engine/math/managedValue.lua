-- Fixed-size numeric values. Weak keys/owners avoid retaining detached values or nodes.
local Managed = {}
local empty = {}
local records = setmetatable({}, { __mode = 'k' })
local prototypes = setmetatable({}, { __mode = 'k' })

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end

function Managed.is(value)
    return type(value) == 'userdata' and records[value] ~= nil
end
-- Engine-only read view. Callers must never mutate this array; public toArray copies.
function Managed.read(value)
    local record = records[value]
    return record and record.values or value
end

function Managed.class(value)
    local record = records[value]
    return record and record.class
end

function Managed.bind(value, owner)
    local record = records[value]
    if record then
        record.owners = record.owners or setmetatable({}, { __mode = 'k' })
        record.owners[owner] = true
    end
    return value
end

function Managed.unbind(value, owner)
    local record = records[value]
    if record and record.owners then
        record.owners[owner] = nil
    end
end

function Managed.create(class, components, aliases, count, owned)
    local prototype = prototypes[class]
    if not prototype then
        prototype = newproxy(true)
        prototypes[class] = prototype
        local mt = getmetatable(prototype)
        mt.__len = function(value)
            return records[value].count
        end
        mt.__index = function(value, key)
            local record = records[value]
            local index = type(key) == 'number' and key or aliases[key]
            if index then
                return record.values[index]
            end
            if key == 'revision' then
                return record.revision
            end
            return class[key]
        end
        mt.__newindex = function(value, key, component)
            local record = records[value]
            local index = type(key) == 'number' and key or aliases[key]
            if not (index and index % 1 == 0 and index >= 1 and index <= record.count) then
                error('Invalid managed value component: ' .. tostring(key), 2)
            end
            assert(finite(component), 'Components must be finite numbers')
            if record.values[index] ~= component then
                record.values[index] = component
                record.revision = record.revision + 1
                for owner in pairs(record.owners or empty) do
                    rawset(
                        owner,
                        '_propertyRevision',
                        (rawget(owner, '_propertyRevision') or 0) + 1
                    )
                end
            end
        end
        for _, name in ipairs({ '__add', '__sub', '__mul', '__div', '__unm', '__tostring' }) do
            mt[name] = class[name]
        end
    end
    local value = newproxy(prototype)
    -- Built-in constructors transfer a fresh private array; external callers still copy.
    local values = owned and components or {}
    for i = 1, count do
        assert(finite(components[i]), 'Components must be finite numbers')
        if not owned then
            values[i] = components[i]
        end
    end
    records[value] = {
        class = class,
        values = values,
        count = count,
        revision = 0,
        -- Allocate weak ownership only for values actually attached to a node.
    }
    return value
end

function Managed.toArray(value)
    local record = assert(records[value], 'Expected a managed numeric value')
    local result = {}
    for i = 1, record.count do
        result[i] = record.values[i]
    end
    return result
end

function Managed.clone(value)
    return records[value].class.fromArray(value)
end

function Managed.unpack(value, first, last)
    local record = records[value]
    if record then
        return unpack(record.values, first or 1, last or record.count)
    end
    return unpack(value, first, last)
end

return Managed
