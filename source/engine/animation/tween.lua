local Array = require('source.engine.math.array')
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Sequence = require('source.engine.animation.sequence')
local Bindings = require('source.engine.animation.bindings')
local Signal = require('source.engine.animation.signal')

local Tween = {}
Tween.__index = Tween

function Tween.new(target, options, goals)
    options = options or {}
    assert(target and not target.destroyed, 'Tween needs a live target')
    local self = setmetatable({
        target = target,
        options = options,
        goals = goals or {},
        state = 'Stopped',
        sequences = {},
        buffers = {},
        elapsed = 0,
        cycles = 0,
        direction = 1,
        delay = 0,
    }, Tween)
    for _, name in ipairs({ 'Started', 'Completed', 'Stopped', 'Resumed' }) do
        self[name] = Signal.new()
    end
    local world = target._world or target._sceneWorld or target.ui and target.ui._sceneWorld
    self.scheduler = options.scheduler or world and world.animations
    assert(self.scheduler, 'Tween target requires a world or explicit scheduler')
    return self
end

function Tween:connect(event, callback)
    return assert(self[event], 'Unknown Tween event'):connect(callback)
end

function Tween:play()
    assert(self.state ~= 'Destroyed', 'Tween was destroyed')
    local duration = self.options.playbackTime or 1
    assert(
        type(duration) == 'number'
            and duration == duration
            and duration > 0
            and duration < math.huge,
        'Tween playbackTime must be positive and finite'
    )
    for _, key in ipairs({ 'delayTime', 'repeatDelay', 'reverseDelay' }) do
        local value = self.options[key] or 0
        assert(
            type(value) == 'number' and value == value and value >= 0 and value < math.huge,
            'Tween delays must be finite and nonnegative'
        )
    end
    local repeats = self.options.repeatCount or 0
    assert(
        repeats >= -1 and repeats == math.floor(repeats),
        'repeatCount must be -1 or a nonnegative integer'
    )
    self.sequences = {}
    for key, value in pairs(self.goals) do
        assert(self.target[key] ~= nil, 'Unknown Tween property: ' .. key)
        self.sequences[key] = Sequence.validate(
            Sequence.linear(Bindings.copy(self.target[key]), Bindings.copy(value))
        )
    end
    for key, points in pairs(self.options.bindings or {}) do
        self.sequences[key] = Sequence.validate(points)
    end
    self.elapsed, self.cycles, self.direction, self.delay = 0, 0, 1, self.options.delayTime or 0
    self.state = 'Playing'
    self.scheduler:add(self)
    self.Started:emit(self)
    return self
end

function Tween:pause()
    if self.state == 'Playing' then
        self.state = 'Paused'
    end
    return self
end

function Tween:resume()
    if self.state == 'Paused' then
        self.state = 'Playing'
        self.scheduler:add(self)
        self.Resumed:emit(self)
    end
    return self
end

function Tween:stop()
    if self.state == 'Playing' or self.state == 'Paused' then
        self.state = 'Stopped'
        self.Stopped:emit(self)
    end
    return self
end

function Tween:apply(time)
    self._sampleTime = time
    if self.options.owner and not self.options.owner.enabled then
        return
    end
    local ramp = self.options.ramp
    if ramp then
        time = ramp:evaluate(time)
    end
    for key, points in pairs(self.sequences) do
        local value = Sequence.evaluate(
            points,
            time,
            self.options.interpolation or 'Linear',
            self.buffers[key]
        )
        if Array.is(value) then
            self.buffers[key] = value
        end
        Bindings.set(self.target, key, value)
    end
end

function Tween:update(dt)
    assert(dt >= 0 and dt < math.huge, 'Invalid Tween delta')
    local duration = self.options.playbackTime or 1
    local cycleLength = duration * (self.options.reverses and 2 or 1)
        + (self.options.reverses and (self.options.reverseDelay or 0) or 0)
        + (self.options.repeatDelay or 0)
    local fullCycles = math.floor(dt / cycleLength)
    if fullCycles > 0 and self.elapsed == 0 and self.direction == 1 and self.delay == 0 then
        local remaining = (self.options.repeatCount or 0) == -1 and fullCycles
            or math.max(0, (self.options.repeatCount or 0) - self.cycles)
        local skipped = math.min(fullCycles, remaining)
        self.cycles = self.cycles + skipped
        dt = dt - skipped * cycleLength
        if skipped > 0 then
            self:apply(self.options.reverses and 0 or 1)
        end
    end
    while dt > 0 and self.state == 'Playing' do
        if self.delay > 0 then
            local used = math.min(dt, self.delay)
            self.delay = self.delay - used
            dt = dt - used
        end
        if dt <= 0 then
            break
        end
        local used = math.min(dt, duration - self.elapsed)
        self.elapsed = self.elapsed + used
        dt = dt - used
        local t = self.elapsed / duration
        self:apply(self.direction == 1 and t or 1 - t)
        if self.elapsed >= duration then
            self.elapsed = 0
            if self.options.reverses and self.direction == 1 then
                self.direction = -1
                self.delay = self.options.reverseDelay or 0
            else
                self.cycles = self.cycles + 1
                if
                    (self.options.repeatCount or 0) ~= -1
                    and self.cycles > (self.options.repeatCount or 0)
                then
                    self.state = 'Completed'
                    self.Completed:emit(self)
                else
                    self.direction = 1
                    self.delay = self.options.repeatDelay or 0
                end
            end
        end
    end
end

function Tween:destroy()
    if self.state == 'Destroyed' then
        return
    end
    self.state = 'Destroyed'
    for _, name in ipairs({ 'Started', 'Completed', 'Stopped', 'Resumed' }) do
        self[name]:release()
    end
end

return Tween
