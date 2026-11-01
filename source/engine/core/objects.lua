-- Runtime objects (images, data, fonts...) are userdata in LÖVE and tables with a class
-- metatable under katsa. Engine code asks this module instead of testing type() directly.
local Objects = {}

-- True for a katsa runtime object (its class defines typeOf), false for plain tables and
-- primitives. Engine nodes and data tables are never runtime objects.
function Objects.isObject(value)
    local kind = type(value)
    if kind == 'userdata' then
        return true
    end
    if kind ~= 'table' then
        return false
    end
    local class = getmetatable(value)
    return class ~= nil and rawget(class, 'typeOf') ~= nil
end

-- Lua type name, reporting runtime objects as 'userdata'.
function Objects.kind(value)
    return Objects.isObject(value) and 'userdata' or type(value)
end

return Objects
