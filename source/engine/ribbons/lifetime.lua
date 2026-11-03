-- Ramp bindings of a ribbon. The coordinate t runs 0..1 along a Beam3D (attachment0 to attachment1)
-- and over the age of a point in a Trail3D (0 = newest, 1 = lifetime). Authored in the child Ramp
-- node named RibbonRamp, exactly like the particle LifetimeRamp.
local Sequence = require('../animation.sequence')

local Lifetime = {}

function Lifetime.defaults(kind)
    return {
        color = Sequence.linear({ 1, 1, 1 }, { 1, 1, 1 }),
        transparency = kind == 'Trail3D' and Sequence.linear(0, 1) or Sequence.linear(0, 0),
        width = Sequence.linear(1, 1),
    }
end

function Lifetime.keys()
    return { width = 1, color = { 1, 1, 1 }, transparency = 0 }
end

function Lifetime.configure(node, bindings)
    local values = Lifetime.defaults(node.ribbonKind)
    for key, points in pairs(bindings or {}) do
        assert(values[key], 'Unknown ribbon ramp key: ' .. tostring(key))
        values[key] = points
    end
    for _, points in pairs(values) do
        Sequence.validate(points)
    end
    node.lifetimeRamp.bindings = values
end

function Lifetime.sample(node, key, t, out)
    local ramp = node.lifetimeRamp
    return Sequence.evaluate(ramp.bindings[key], t, ramp.interpolation, out)
end

return Lifetime
