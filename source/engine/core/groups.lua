local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Scene-local symmetric interaction matrix; bit masks are compiled implementation data.
local bit = require('bit')

local Groups = {}
Groups.__index = Groups

function Groups.new(onChanged)
    local self = setmetatable(
        { names = {}, bits = {}, masks = {}, revision = 0, onChanged = onChanged },
        Groups
    )
    self:add('Default')
    return self
end

function Groups:canonical(name)
    return name == 'default' and 'Default' or name
end

function Groups:changed()
    self.revision = self.revision + 1
    if self.onChanged then
        self.onChanged(self)
    end
end

function Groups:add(name)
    name = self:canonical(name)
    assert(
        type(name) == 'string' and name:match('%S') and not name:find('[\r\n]'),
        'Group name must be nonempty single-line text'
    )
    if self.bits[name] then
        return self.bits[name]
    end
    assert(#self.names < 30, 'This backend supports 30 named groups')
    local used = {}
    for _, v in pairs(self.bits) do
        used[v] = true
    end
    local value = 1
    while used[value] do
        value = value * 2
    end
    self.names[#self.names + 1] = name
    self.bits[name] = value
    self.masks[name] = -1
    -- New groups interact with existing groups; existing exclusions remain intact.
    for key, mask in pairs(self.masks) do
        self.masks[key] = bit.bor(mask, value)
    end
    self:changed()
    return value
end

function Groups:interacts(a, b)
    a, b = self:canonical(a), self:canonical(b)
    assert(self.bits[a] and self.bits[b], 'Unknown group')
    return bit.band(self.masks[a], self.bits[b]) ~= 0
end

function Groups:set(a, b, enabled)
    a, b = self:canonical(a), self:canonical(b)
    assert(self.bits[a] and self.bits[b], 'Unknown group')

    local function assign(x, y)
        self.masks[x] = enabled and bit.bor(self.masks[x], self.bits[y])
            or bit.band(self.masks[x], bit.bnot(self.bits[y]))
    end
    assign(a, b)
    assign(b, a)
    self:changed()
end

function Groups:rename(old, name)
    old = self:canonical(old)
    assert(old ~= 'Default', 'Default group cannot be renamed')
    assert(
        self.bits[old]
            and type(name) == 'string'
            and name:match('%S')
            and not self.bits[name]
            and not name:find('[\r\n]'),
        'Invalid or duplicate group name'
    )
    self.bits[name], self.masks[name] = self.bits[old], self.masks[old]
    self.bits[old], self.masks[old] = nil, nil
    for i, v in ipairs(self.names) do
        if v == old then
            self.names[i] = name
        end
    end
    self.renamed = { old, name }
    self:changed()
    self.renamed = nil
end

function Groups:remove(name)
    name = self:canonical(name)
    assert(name ~= 'Default' and self.bits[name], 'Default cannot be removed / unknown group')
    self.bits[name], self.masks[name] = nil, nil
    for i, v in ipairs(self.names) do
        if v == name then
            table.remove(self.names, i)
            break
        end
    end
    self.removed = name
    self:changed()
    self.removed = nil
end

return Groups
