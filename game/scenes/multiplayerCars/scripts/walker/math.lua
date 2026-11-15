local Math = {}

function Math.approach(value, target, amount)
    return value < target and math.min(target, value + amount) or math.max(target, value - amount)
end

function Math.clamp01(value)
    return math.min(1, math.max(0, value))
end

-- Moves an angle in radians toward `target` along the short way by `weight` of the gap.
function Math.angle(value, target, weight)
    local delta = (target - value + math.pi) % (2 * math.pi) - math.pi
    return value + delta * weight
end

return Math
