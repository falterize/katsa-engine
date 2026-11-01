local pairs = require('source.engine.math.array').pairs
local Sequence = require('source.engine.animation.sequence')

local Lifetime = {}

function Lifetime.defaults()
    return {
        size = { { time = 0, value = 1 }, { time = 0.5, value = 1.5 }, { time = 1, value = 0 } },
        transparency = {
            { time = 0, value = 0 },
            { time = 0.5, value = 0.2 },
            { time = 1, value = 1 },
        },
        color = Sequence.linear({ 1, 1, 1 }, { 1, 1, 1 }),
        rotation = Sequence.linear(0, 0),
    }
end

function Lifetime.configure(emitter, bindings)
    local values = Lifetime.defaults()
    for key, points in pairs(bindings or {}) do
        values[key] = points
    end
    for _, points in pairs(values) do
        Sequence.validate(points)
    end
    emitter.lifetimeRamp.bindings = values
end

return Lifetime
