local ipairs = require('../../math.array').ipairs
local Node = require('../core.baseNode')

local Track = Node.define('AnimationTrack', 'Node')
Track.propertySchema = {
    playing = {},
    speed = {},
    looped = {},
    timePosition = { min = 0 },
    weight = { min = 0, max = 1 },
    order = {},
    fadeIn = { min = 0 },
    fadeOut = { min = 0 },
    boneMask = { kind = 'bindings' },
    startTime = { min = 0 },
    endTime = { min = 0 },
    loopMode = { options = { 'Linear', 'PingPong' } },
    additive = {},
    subtract = {},
    additiveReference = { options = { 'firstFrame', 'rest' } },
}

function Track.initialize(self)
    self.speed = self.speed or 1
    self.looped = self.looped ~= false
    self.timePosition = 0
    self.weight = self.weight or 1
    self.order = self.order or rawget(self, 'priority') or 0
    rawset(self, 'priority', nil)
    self.fadeIn = self.fadeIn or 0
    self.fadeOut = self.fadeOut or 0
    self.boneMask = self.boneMask or {}
    self.state = 'Stopped'
    self._blendWeight = 0
    self._buffers = {}
end

function Track:setPlaying(value)
    if value then
        self:play()
    else
        self:pause()
    end
end

function Track:fade(weight, duration)
    assert(weight >= 0 and weight <= 1 and (duration or 0) >= 0, 'Invalid animation fade')
    self._fadeFrom, self._fadeTarget, self._fadeDuration, self._fadeTime =
        self._blendWeight, weight, duration or 0, 0
    if self._fadeDuration == 0 then
        self._blendWeight = weight
    end
end

-- The part of the clip that plays: `startTime` .. `endTime` (the whole clip by default).
function Track:range()
    local duration = self.clip.duration
    local from = math.max(0, math.min(self.startTime or 0, duration))
    local to = math.max(from, math.min(self.endTime or duration, duration))
    return from, to
end

function Track:play(fade, speed, weight)
    if speed ~= nil then
        self.speed = speed
    end
    if weight ~= nil then
        self.weight = weight
    end
    fade = fade == nil and self.fadeIn or fade
    assert(not self.destroyed, 'AnimationTrack was destroyed')
    local from, to = self:range()
    self.timePosition, self._loops, self.state = self.speed < 0 and to or from, 0, 'Playing'
    rawset(self, '_playing', true)
    self._animator._rootTrack = nil
    self:fade(self.weight, fade or 0)
    self:emit('Started', self)
    return self
end

function Track:pause()
    self.state = 'Paused'
    rawset(self, '_playing', false)
    return self
end

function Track:resume()
    self.state = 'Playing'
    rawset(self, '_playing', true)
    return self
end

function Track:stop(fade)
    fade = fade == nil and self.fadeOut or fade
    rawset(self, '_playing', false)
    self:fade(0, fade or 0)
    self.state = (fade or 0) > 0 and 'Fading' or 'Stopped'
    self:emit('Stopped', self)
    return self
end

function Track:advance(dt)
    assert(
        type(self.weight) == 'number' and self.weight >= 0 and self.weight <= 1,
        'Animation weight must be within 0..1'
    )
    assert(
        type(self.order) == 'number' and math.abs(self.order) < math.huge,
        'Animation priority must be finite'
    )
    if self.state == 'Stopped' then
        return
    end
    if self._fadeDuration and self._fadeTime < self._fadeDuration then
        self._fadeTime = math.min(self._fadeDuration, self._fadeTime + dt)
        self._blendWeight = self._fadeFrom
            + (self._fadeTarget - self._fadeFrom) * self._fadeTime / self._fadeDuration
        if self.state == 'Fading' and self._fadeTime == self._fadeDuration then
            self.state = 'Stopped'
            return
        end
    else
        self._blendWeight = self.state == 'Fading' and 0 or self.weight
    end
    if self.state == 'Paused' then
        return
    end
    assert(
        type(self.speed) == 'number'
            and self.speed == self.speed
            and math.abs(self.speed) < math.huge,
        'Animation speed must be finite'
    )
    local from, to = self:range()
    local duration = to - from
    local old = self.timePosition
    local total = old + dt * self.speed
    local pingPong = self.loopMode == 'PingPong'
    local loops = self.looped and duration > 0 and math.floor((total - from) / duration) or 0
    local time
    if duration <= 0 then
        time = from
    elseif not self.looped then
        time = math.max(from, math.min(total, to))
    elseif pingPong then
        -- The unfolded position runs on; the visible time goes forward on even cycles and backward
        -- on odd ones. A seek (timePosition changed from outside) restarts the unfolding.
        local unfolded = self._lastTime == old and self._unfolded or old - from
        unfolded = unfolded + dt * self.speed
        self._unfolded = unfolded
        local phase = unfolded % (2 * duration)
        time = from + (phase < duration and phase or 2 * duration - phase)
        loops = math.floor(unfolded / (2 * duration)) - math.floor((unfolded - dt * self.speed) / (2 * duration))
    else
        time = from + (total - from) % duration
    end
    for _, marker in ipairs(self.clip.markers) do
        local hits = 0
        if self.looped and duration > 0 and marker.time >= from and marker.time <= to then
            hits = math.floor((total - marker.time) / duration)
                - math.floor((old - marker.time) / duration)
        elseif not self.looped and marker.time > old and marker.time <= time then
            hits = 1
        end
        for _ = 1, math.min(64, math.abs(hits)) do
            self:emit('Marker', marker.name, marker.value, self)
            self:emit('Marker:' .. marker.name, marker.value, self)
        end
    end
    self._loops = (self._loops or 0) + loops
    self.timePosition = time
    self._lastTime = time
    if
        not self.looped and (self.speed >= 0 and total >= to or self.speed < 0 and total <= from)
    then
        self.state = 'Paused'
        rawset(self, '_playing', false)
        self:emit('Completed', self)
    end
end

return Track
