local StepValue = {}
StepValue.__index = StepValue

local TWO_PI = math.pi * 2

-- A value authored once per fixed simulation step, sampled at render time with the same
-- previous/current alpha that interpolated bodies use. Without it, per-tick gameplay state
-- (facing, blend weights) advances in visible steps whenever the world clock is slowed.

function StepValue.new(initial, angular)
    initial = initial or 0
    return setmetatable(
        { previous = initial, current = initial, angular = angular == true },
        StepValue
    )
end

-- Call exactly once per fixed step, after the step changed the value.
function StepValue:capture(value)
    self.previous, self.current = self.current, value
    return value
end

-- Teleports and scene starts must not blend from stale history.
function StepValue:reset(value)
    self.previous, self.current = value, value
end

function StepValue:sample(alpha)
    alpha = alpha < 0 and 0 or (alpha > 1 and 1 or alpha)
    local a, b = self.previous, self.current
    if self.angular then
        local delta = (b - a + math.pi) % TWO_PI - math.pi
        return a + delta * alpha
    end
    return a + (b - a) * alpha
end

-- Matches Body3D:getRenderMatrix: paused or non-interpolating solvers show the latest state.
function StepValue.alphaOf(physics)
    if not physics or not physics.interpolate or physics.paused then
        return 1
    end
    return physics.interpolationAlpha or 1
end

function StepValue:sampleFor(physics)
    return self:sample(StepValue.alphaOf(physics))
end

return StepValue
