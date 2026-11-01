-- Internal array adapters; public callers can explicitly request value:toArray().
local Managed = require('source.engine.math.managedValue')

local Array = {}

function Array.is(value)
    return type(value) == 'table' or Managed.is(value)
end

function Array.ipairs(value)
    if type(value) == 'table' then
        return ipairs(value)
    end
    return ipairs(Managed.read(value))
end

function Array.pairs(value)
    if type(value) == 'table' then
        return pairs(value)
    end
    return pairs(Managed.read(value))
end
Array.unpack = Managed.unpack
return Array
