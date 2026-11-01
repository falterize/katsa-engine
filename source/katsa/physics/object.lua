-- Shared helpers for physics classes: class creation with LÖVE-style type()/typeOf(), liveness
-- checks and ordered access to object sets.
local Object = {}

function Object.class(name)
    local class = {}
    class.__index = class
    function class:type()
        return name
    end

    function class:typeOf(other)
        return other == name or other == 'Object'
    end

    function class:release()
        return self.destroy and self:destroy() or true
    end
    return class
end

function Object.alive(self, name)
    if self._destroyed then
        error('Attempt to use destroyed ' .. name, 3)
    end
end

-- Objects in a set, ordered by creation (registry id).
function Object.sortedKeys(set)
    local list = {}
    for item in pairs(set) do
        list[#list + 1] = item
    end
    table.sort(list, function(a, b)
        return a._id < b._id
    end)
    return list
end

function Object.count(set)
    local n = 0
    for _ in pairs(set) do
        n = n + 1
    end
    return n
end

return Object
