local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
-- Shader layers behave like layer groups: a symmetric interaction matrix. Layers start as
-- Default2D (Shader2D) and Default3D (Shader3D and the 3D render). Priority orders effects.
--   * A Shader2D processes the 3D render only if its layer interacts with Default3D.
--   * Effects whose layers do not interact cannot combine on the same object or region:
--     the higher-priority layer wins and suppresses the lower one.
local Layers = {}
Layers.__index = Layers

local MAX = 30

function Layers.new(onChanged)
    local self = setmetatable({
        names = { 'Default2D', 'Default3D' },
        priorities = { Default2D = 0, Default3D = 0 },
        links = { Default2D = { Default3D = false }, Default3D = { Default2D = false } },
        blocked = {},
        onChanged = onChanged,
        revision = 0,
    }, Layers)
    return self
end

function Layers:changed(info)
    self.revision = self.revision + 1
    if self.onChanged then
        self.onChanged(self, info)
    end
end

function Layers:add(name, priority)
    assert(
        type(name) == 'string' and name:match('%S') and not name:find('[\r\n]'),
        'Shader layer name must be nonempty single-line text'
    )
    assert(not self.priorities[name], 'Duplicate shader layer')
    assert(#self.names < MAX, 'At most ' .. MAX .. ' shader layers')
    assert(not priority or priority > 0, 'Custom shader layers must be above the defaults')
    self.priorities[name] = priority or #self.names * 10
    self.links[name] = {}
    self.names[#self.names + 1] = name
    self:changed()
end

local function isDefault(name)
    return name == 'Default2D' or name == 'Default3D'
end

function Layers:remove(name)
    assert(self.priorities[name], 'Unknown shader layer: ' .. tostring(name))
    assert(not isDefault(name), 'Default shader layers cannot be removed')
    for index, existing in ipairs(self.names) do
        if existing == name then
            table.remove(self.names, index)
            break
        end
    end
    self.priorities[name], self.links[name] = nil, nil
    for _, other in pairs(self.links) do
        other[name] = nil
    end
    self:changed({ removed = name })
end

function Layers:rename(old, name)
    assert(self.priorities[old], 'Unknown shader layer: ' .. tostring(old))
    assert(not isDefault(old), 'Default shader layers cannot be renamed')
    assert(type(name) == 'string' and name:match('%S'), 'Shader layer name must not be empty')
    assert(not self.priorities[name], 'Duplicate shader layer')
    for index, existing in ipairs(self.names) do
        if existing == old then
            self.names[index] = name
        end
    end
    self.priorities[name], self.priorities[old] = self.priorities[old], nil
    self.links[name], self.links[old] = self.links[old], nil
    for _, other in pairs(self.links) do
        other[name], other[old] = other[old], nil
    end
    self:changed({ renamed = { old, name } })
end

function Layers:priority(name)
    return assert(self.priorities[name], 'Unknown shader layer: ' .. tostring(name))
end

function Layers:setPriority(name, value)
    assert(
        type(value) == 'number' and value == value and math.abs(value) < math.huge,
        'Invalid layer priority'
    )
    assert(not isDefault(name) or value == 0, 'Default layers stay at priority 0')
    assert(isDefault(name) or value > 0, 'Custom shader layers must stay above the defaults')
    self:priority(name)
    self.priorities[name] = value
    self:changed()
end

function Layers:interacts(a, b)
    self:priority(a)
    self:priority(b)
    if a == b then
        return true
    end
    return self.links[a][b] ~= false
end

function Layers:setInteracts(a, b, enabled)
    self:priority(a)
    self:priority(b)
    assert(a ~= b, 'A layer always interacts with itself')
    self.links[a][b] = enabled == true
    self.links[b][a] = enabled == true
    self:changed()
end

-- A higher layer suppresses a lower layer it does not interact with.
function Layers:suppresses(upper, lower)
    return self:priority(upper) > self:priority(lower) and not self:interacts(upper, lower)
end

-- Whether effects in `name` may process the 3D render.
function Layers:affects3D(name)
    return self:interacts(name, 'Default3D')
end

function Layers:resolve(nodes, out)
    out = out or {}
    for i = #out, 1, -1 do
        out[i] = nil
    end
    for _, node in ipairs(nodes) do
        if node.enabled ~= false and not node.destroyed then
            local suppressed = false
            for _, upper in ipairs(nodes) do
                if
                    upper.enabled ~= false
                    and not upper.destroyed
                    and self:suppresses(upper.shaderLayer, node.shaderLayer)
                then
                    suppressed = true
                    break
                end
            end
            if not suppressed then
                out[#out + 1] = node
            end
        end
    end
    table.sort(out, function(a, b)
        local pa, pb = self:priority(a.shaderLayer), self:priority(b.shaderLayer)
        return pa == pb and (a.zIndex or 0) < (b.zIndex or 0) or pa < pb
    end)
    return out
end

return Layers
