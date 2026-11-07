-- Time units of a Ramp's keyframe tracks. Tracks are stored normalized (point time 0..1, the
-- format every consumer samples), but an Animated Ramp is authored in seconds: a point can sit at
-- any time and the animation lasts until its last point, like an F-curve. A Ramp that is sampled
-- by something else (particle lifetime, gradient stops) stays on the fixed 0..1 axis.
local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs

local Timeline = {}

local MIN_DURATION = 0.0001
-- An hour: far beyond any authored animation, and small enough that the editor's graph (120 px
-- per second) stays a sane size.
Timeline.MAX_DURATION = 3600

-- True when the Ramp's tracks are authored in seconds.
function Timeline.usesSeconds(ramp)
    return ramp.mode == 'Animated' and not ramp:isLifetime()
end

-- Length of the time axis in seconds; 1 for the fixed 0..1 axis.
function Timeline.duration(ramp)
    return Timeline.usesSeconds(ramp) and ramp.playbackTime or 1
end

function Timeline.toSeconds(ramp, time)
    return time * Timeline.duration(ramp)
end

function Timeline.fromSeconds(ramp, seconds)
    return seconds / Timeline.duration(ramp)
end

local function scaleTimes(points, factor)
    for _, point in ipairs(points) do
        point.time = point.time * factor
        for _, name in ipairs({ 'incoming', 'outgoing' }) do
            local handle = point[name]
            if handle then
                handle[1] = handle[1] * factor
            end
        end
    end
end

-- Changes the duration to `seconds`. Every point keeps the second it was at, so the stored
-- normalized times are rescaled by old / new.
function Timeline.setDuration(ramp, seconds)
    assert(Timeline.usesSeconds(ramp), 'Only an Animated Ramp has a time axis in seconds')
    assert(type(seconds) == 'number' and seconds >= MIN_DURATION, 'Duration must be positive')
    assert(seconds <= Timeline.MAX_DURATION, 'An animation can last at most 3600 seconds')
    local factor = ramp.playbackTime / seconds
    if factor ~= 1 then
        for _, points in pairs(ramp.bindings) do
            scaleTimes(points, factor)
        end
        ramp.playbackTime = seconds
    end
end

-- Makes the last point of `points` the end of the animation (the longest track decides when
-- several properties are animated).
function Timeline.fit(ramp)
    if not Timeline.usesSeconds(ramp) then
        return
    end
    local last = 0
    for _, points in pairs(ramp.bindings) do
        last = math.max(last, points[#points].time)
    end
    if last > 0 and last ~= 1 then
        Timeline.setDuration(ramp, math.max(MIN_DURATION, ramp.playbackTime * last))
    end
end

return Timeline
