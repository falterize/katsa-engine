-- Leaf: plays one clip. The tree owns the AnimationTrack; the leaf only receives a weight.
local Animation = {}
Animation.__index = Animation

local LOOP_MODES = { None = true, Linear = true, PingPong = true }

-- definition: { clip = 'Walk' | index | clip table, speed = 1, loop = true, order = 0,
--               mask = { BoneName = 1 }, retarget = {...},
--               playMode = 'Forward' | 'Backward',
--               loopMode = 'None' | 'Linear' | 'PingPong'   (overrides `loop`),
--               startTime = seconds, endTime = seconds,       (play only this part of the clip)
--               stretch = 1 }                                 (extra speed factor of the part)
function Animation.new(definition)
    assert(definition.clip ~= nil, 'An Animation node needs a clip')
    local loopMode = definition.loopMode
    assert(loopMode == nil or LOOP_MODES[loopMode], 'loopMode must be None, Linear or PingPong')
    local playMode = definition.playMode or 'Forward'
    assert(playMode == 'Forward' or playMode == 'Backward', 'playMode must be Forward or Backward')
    local loop = definition.loop ~= false
    if loopMode then
        loop = loopMode ~= 'None'
    end
    return setmetatable({
        kind = 'Animation',
        definition = definition,
        loop = loop,
        loopMode = loop and loopMode == 'PingPong' and 'PingPong' or 'Linear',
        speed = (definition.speed or 1) * (definition.stretch or 1) * (playMode == 'Backward' and -1 or 1),
        children = {},
    }, Animation)
end

function Animation:collect(list)
    list[#list + 1] = self
end

function Animation:evaluate(weight, scale, context)
    context:add(self, weight, scale)
end

-- The part of the clip that plays, in seconds: from, to.
function Animation:range()
    return self.track:range()
end

function Animation:restart()
    local track = self.track
    if track then
        local from, to = track:range()
        track.timePosition, track._loops = track.speed < 0 and to or from, 0
        if track.state ~= 'Playing' then
            track:resume()
        end
    end
end

function Animation:finished()
    local track = self.track
    return track ~= nil and not self.loop and track.state == 'Paused'
end

-- Length of the played part (before speed).
function Animation:duration()
    if not self.track then
        return 0
    end
    local from, to = self.track:range()
    return to - from
end

-- Position within the played part, 0..1.
function Animation:phase()
    local from = self.track:range()
    local length = self:duration()
    return length > 0 and math.max(0, math.min(1, (self.track.timePosition - from) / length)) or 0
end

function Animation:setPhase(phase)
    local from = self.track:range()
    self.track.timePosition = from + phase * self:duration()
end

-- Moves to `seconds` within the played part.
function Animation:seek(seconds)
    local from = self.track:range()
    local length = self:duration()
    seconds = length > 0 and (self.loop and seconds % length or math.min(seconds, length)) or 0
    self.track.timePosition = from + seconds
end

-- Seconds until the clip reaches its end (its start when it plays backward).
function Animation:remaining()
    local from, to = self.track:range()
    local track = self.track
    local speed = math.max(math.abs(track.speed), 1e-6)
    if track.speed < 0 then
        return (track.timePosition - from) / speed
    end
    return (to - track.timePosition) / speed
end

return Animation
