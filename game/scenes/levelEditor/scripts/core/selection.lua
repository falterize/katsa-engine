-- The ordered set of selected items (any values usable as table keys). The last added item is
-- the primary one: it drives the properties panel and the gizmo pivot. Pure Lua.
local unpack = table.unpack or unpack

local Selection = {}
Selection.__index = Selection

function Selection.new()
    return setmetatable({ list = {}, index = {}, listeners = {} }, Selection)
end

local function changed(self)
    for _, listener in ipairs(self.listeners) do
        listener(self)
    end
end

function Selection:onChange(listener)
    self.listeners[#self.listeners + 1] = listener
end

function Selection:has(item)
    return self.index[item] ~= nil
end

function Selection:count()
    return #self.list
end

function Selection:primary()
    return self.list[#self.list]
end

function Selection:set(items)
    self.list, self.index = {}, {}
    for _, item in ipairs(items or {}) do
        if not self.index[item] then
            self.list[#self.list + 1] = item
            self.index[item] = true
        end
    end
    changed(self)
end

function Selection:clear()
    if #self.list > 0 then
        self:set({})
    end
end

function Selection:add(item)
    if not self.index[item] then
        self.list[#self.list + 1] = item
        self.index[item] = true
        changed(self)
    end
end

function Selection:remove(item)
    if not self.index[item] then
        return
    end
    for position, value in ipairs(self.list) do
        if value == item then
            table.remove(self.list, position)
            break
        end
    end
    self.index[item] = nil
    changed(self)
end

function Selection:toggle(item)
    if self.index[item] then
        self:remove(item)
    else
        self:add(item)
    end
end

-- A copy, safe to keep while the selection changes.
function Selection:items()
    return { unpack(self.list) }
end

return Selection
