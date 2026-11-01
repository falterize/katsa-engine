-- Pixel/meter conversion. Lengths, velocities and forces scale with the meter; torque and inertia
-- scale with its square; mass does not scale.
local meter = 30

local Scale = {}

function Scale.setMeter(value)
    assert(value >= 1 and value <= 1000, 'Physics error: invalid meter')
    meter = value
end

function Scale.getMeter()
    return meter
end

function Scale.up(value)
    return value * meter
end

function Scale.down(value)
    return value / meter
end

function Scale.square(value)
    return value * meter * meter
end

function Scale.squareDown(value)
    return value / (meter * meter)
end

return Scale
