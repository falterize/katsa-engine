local Time = {}
Time.__index = Time

function Time.new()
    return setmetatable({ scale = 1, elapsed = 0, realTime = 0, delta = 0, realDelta = 0 }, Time)
end

function Time:setScale(scale)
    assert(
        type(scale) == 'number' and scale == scale and scale >= 0 and scale <= 8,
        'time scale must be a finite number between 0 and 8'
    )
    self.scale = scale
end

function Time:update(dt, blocked)
    assert(
        type(dt) == 'number' and dt >= 0 and dt < math.huge,
        'time delta must be finite and non-negative'
    )
    assert(self.scale >= 0 and self.scale <= 8 and self.scale == self.scale, 'Invalid time.scale')
    self.realDelta = dt
    self.realTime = self.realTime + dt
    self.delta = blocked and 0 or dt * self.scale
    self.elapsed = self.elapsed + self.delta
    return self.delta
end

function Time:physicsStep(world, dt)
    -- Call once from an unscaled update; do not multiply an already scaled delta again.
    world:update(dt * self.scale)
end

return Time
