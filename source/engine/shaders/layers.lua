local ipairs = require('source.engine.math.array').ipairs
-- Directed suppression: higher enabled layers can suppress lower layers.
local Layers = {}
Layers.__index = Layers

function Layers.new()
    return setmetatable(
        {
            names = { 'Default' },
            priorities = { Default = 0 },
            suppression = {},
            blocked3D = {},
            revision = 0,
        },
        Layers
    )
end

function Layers:add(name, priority)
    assert(
        type(name) == 'string' and name ~= '' and not self.priorities[name],
        'Duplicate/empty shader layer'
    )
    assert(not priority or priority > 0, 'Custom shader layers must be above Default')
    self.priorities[name] = priority or #self.names * 10
    self.names[#self.names + 1] = name
    self.revision = self.revision + 1
end

function Layers:priority(name)
    return assert(self.priorities[name], 'Unknown shader layer: ' .. tostring(name))
end

function Layers:setPriority(name, value)
    assert(
        type(value) == 'number' and value == value and math.abs(value) < math.huge,
        'Invalid layer priority'
    )
    assert(name ~= 'Default' or value == 0, 'Default remains at priority 0')
    assert(name == 'Default' or value > 0, 'Custom shader layers must stay above Default')
    self:priority(name)
    self.priorities[name] = value
    self.revision = self.revision + 1
end

function Layers:setSuppressed(upper, lower, enabled)
    assert(self:priority(upper) > self:priority(lower), 'Only higher layers suppress lower layers')
    self.suppression[upper] = self.suppression[upper] or {}
    self.suppression[upper][lower] = enabled == true
    self.revision = self.revision + 1
end

function Layers:suppresses(upper, lower)
    return self:priority(upper) > self:priority(lower)
            and self.suppression[upper]
            and self.suppression[upper][lower]
        or false
end

-- A layer may forbid its Shader2D nodes from touching the 3D scene (default: allowed). A node
-- affects 3D only when its own `affects3D` is set and its layer allows it.
function Layers:affects3D(name)
    self:priority(name)
    return not self.blocked3D[name]
end

function Layers:setAffects3D(name, enabled)
    self:priority(name)
    self.blocked3D[name] = enabled == false or nil
    self.revision = self.revision + 1
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
