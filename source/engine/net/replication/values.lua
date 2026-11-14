local Managed = require('../../math.managedValue')

-- Value helpers for replication: what may cross the network, and how to tell that it changed.
local Values = {}

local MAX_DEPTH = 6

local function isNode(value)
    return type(value) == 'table' and rawget(value, '_node') == true
end

-- Keeps one kind of key: a table with string keys is a map, otherwise an array.
local function pruneKeys(copy)
    local count = 0
    for _ in pairs(copy) do
        count = count + 1
    end
    if count == #copy then
        return
    end
    for key in pairs(copy) do
        if type(key) ~= 'string' then
            copy[key] = nil
        end
    end
end

-- Plain copy of a replicable value (booleans, numbers, strings, vectors and tables of them),
-- or nil for functions, nodes and anything else that cannot cross the network.
function Values.plain(value, depth)
    local kind = type(value)
    if kind == 'boolean' or kind == 'number' or kind == 'string' then
        return value
    end
    depth = (depth or 0) + 1
    if depth > MAX_DEPTH or isNode(value) then
        return nil
    end
    if kind == 'userdata' and Managed.is(value) then
        value, kind = Managed.toArray(value), 'table'
    end
    if kind ~= 'table' then
        return nil
    end
    local copy = {}
    for key, item in pairs(value) do
        local converted = (type(key) == 'number' or type(key) == 'string')
            and Values.plain(item, depth)
        if converted ~= nil then
            copy[key] = converted
        end
    end
    pruneKeys(copy)
    return copy
end

function Values.equal(a, b)
    if a == b then
        return true
    end
    if type(a) ~= 'table' or type(b) ~= 'table' then
        return false
    end
    for key, value in pairs(a) do
        if not Values.equal(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Compares two maps. Returns the entries that are new or different, and the removed keys.
function Values.diff(old, new)
    local changed, removed
    for key, value in pairs(new) do
        if not Values.equal(old[key], value) then
            changed = changed or {}
            changed[key] = value
        end
    end
    for key in pairs(old) do
        if new[key] == nil then
            removed = removed or {}
            removed[#removed + 1] = key
        end
    end
    return changed, removed
end

return Values
