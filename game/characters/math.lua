local Math = {}

function Math.approach(value, target, amount)
    return value < target and math.min(target, value + amount) or math.max(target, value - amount)
end

function Math.angle(value, target, weight)
    local delta = (target - value + math.pi) % (2 * math.pi) - math.pi
    return value + delta * weight
end

return Math
