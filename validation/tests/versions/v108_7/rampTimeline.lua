-- Ramp keyframes in seconds: tracks stay normalized, the duration rescales them so each point
-- keeps its second, and the last point decides when the animation ends.
local Timeline = require('source.engine.animation.rampTimeline')
local Sequence = require('source.engine.animation.sequence')

local Module = {}

local function ramp(mode, duration)
    return {
        mode = mode,
        playbackTime = duration,
        isLifetime = function()
            return false
        end,
        bindings = { position = Sequence.linear(0, 10) },
    }
end

function Module.run(self)
    local animated = ramp('Animated', 4)
    animated.bindings.position[2].time = 0.5
    animated.bindings.position[2].incoming = { 0.4, 0.5 }
    self:check(Timeline.toSeconds(animated, 0.5) == 2, 'normalized time converts to seconds')
    Timeline.setDuration(animated, 8)
    local last = animated.bindings.position[2]
    self:check(last.time == 0.25 and last.incoming[1] == 0.2, 'lengthening keeps every point at its second')
    Timeline.fit(animated)
    self:check(
        animated.playbackTime == 2 and animated.bindings.position[2].time == 1,
        'the last point becomes the end of the animation'
    )
    local gradient = ramp('Static', 4)
    self:check(Timeline.duration(gradient) == 1 and not Timeline.usesSeconds(gradient), 'a Static Ramp keeps the 0..1 axis')
    self:check(not pcall(Timeline.setDuration, gradient, 2), 'a Static Ramp has no duration to change')
    local lifetime = ramp('Animated', 4)
    lifetime.isLifetime = function()
        return true
    end
    self:check(not Timeline.usesSeconds(lifetime), 'a lifetime Ramp stays on the 0..1 axis')
end

return Module
