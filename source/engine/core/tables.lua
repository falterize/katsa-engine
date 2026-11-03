-- Table copying shared by the engine and plugins.
local Array = require('source.engine.math.array')
local Managed = require('source.engine.math.managedValue')
local pairs = Array.pairs

local Tables = {}

-- Deep copy of plain data tables. Non-table values are returned unchanged.
function Tables.copy(value)
    if type(value) ~= 'table' then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = Tables.copy(item)
    end
    return result
end

-- Deep copy of authored property values: managed values are cloned, arrays and tables copied,
-- everything else (including tracked nodes, which belong to the scene) is shared.
function Tables.copyAuthored(value)
    if Managed.is(value) then
        return value:clone()
    end
    if not Array.is(value) or value._node then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = Tables.copyAuthored(item)
    end
    return result
end

return Tables
