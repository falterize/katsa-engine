local pairs = require('../../math.array').pairs

-- Attributes: named values any node can carry, like Roblox's Instance:SetAttribute. A value can be
-- a boolean, number, string, vector (a list of numbers), any table, a function or a reference to
-- another node. Attributes are public data of the node: scripts read them, the Workspace
-- inspector lists and edits them, and Node:clone copies them (node references stay shared).
--
--   node:setAttribute('health', 80)          node:getAttribute('health')        --> 80
--   node:setAttribute('target', otherNode)   node:getAttribute('target')        --> otherNode
--   node:setAttribute('health', nil)         -- removes it
--   node:onAttributeChanged('health', function(value) ... end)
--   node:connect('AttributeChanged', function(name, value) ... end)
--
-- A reference to a node that was destroyed reads as nil. `setAttributeReference(name, node)` keeps
-- an empty node slot while the value is nil (the inspector uses it for "None").
local Attributes = {}

local function check(self, name)
    assert(not self.destroyed and not self._destroying, 'Attributes require a live node')
    assert(type(name) == 'string' and name ~= '', 'Attribute name must be a nonempty string')
end

local function isNode(value)
    return type(value) == 'table' and rawget(value, '_node') == true
end

local function changed(self, name, value)
    self:emit('AttributeChanged', name, value)
    self:emit('AttributeChanged:' .. name, value)
end

function Attributes.set(self, name, value)
    check(self, name)
    local values = self._attributes
    if value == nil then
        if values and values[name] ~= nil or self._attributeSlots and self._attributeSlots[name] then
            if values then
                values[name] = nil
            end
            if self._attributeSlots then
                self._attributeSlots[name] = nil
            end
            changed(self, name, nil)
        end
        return self
    end
    values = values or {}
    self._attributes = values
    if self._attributeSlots then
        self._attributeSlots[name] = nil
    end
    if values[name] ~= value or type(value) == 'table' then
        values[name] = value
        changed(self, name, value)
    end
    return self
end

function Attributes.setReference(self, name, node)
    check(self, name)
    assert(node == nil or isNode(node), 'Attribute reference must be a node or nil')
    if node then
        return Attributes.set(self, name, node)
    end
    self._attributes = self._attributes or {}
    self._attributeSlots = self._attributeSlots or {}
    local had = self._attributes[name]
    self._attributes[name], self._attributeSlots[name] = nil, true
    if had ~= nil then
        changed(self, name, nil)
    end
    return self
end

function Attributes.get(self, name, default)
    local value = self._attributes and self._attributes[name]
    if isNode(value) and value.destroyed then
        value = nil
    end
    if value == nil then
        return default
    end
    return value
end

-- A fresh { name = value } table of the live attributes.
function Attributes.all(self)
    local result = {}
    for name in pairs(self._attributes or {}) do
        local value = Attributes.get(self, name)
        if value ~= nil then
            result[name] = value
        end
    end
    return result
end

-- Names in a stable order (empty node slots included), for editors.
function Attributes.names(self)
    local names = {}
    for name in pairs(self._attributes or {}) do
        names[#names + 1] = name
    end
    for name in pairs(self._attributeSlots or {}) do
        if not (self._attributes and self._attributes[name] ~= nil) then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

-- True when the attribute holds (or is reserved for) a node reference.
function Attributes.isReference(self, name)
    local value = self._attributes and self._attributes[name]
    return isNode(value) or (self._attributeSlots ~= nil and self._attributeSlots[name] == true)
end

function Attributes.onChanged(self, name, callback)
    assert(type(name) == 'string' and name ~= '', 'Attribute name must be a nonempty string')
    return self:connect('AttributeChanged:' .. name, callback)
end

-- A table whose fields read and write the attributes (for editors that expect a container).
function Attributes.view(self)
    return setmetatable({}, {
        __index = function(_, name)
            return Attributes.get(self, name)
        end,
        __newindex = function(_, name, value)
            Attributes.set(self, name, value)
        end,
    })
end

return Attributes
