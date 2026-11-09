-- Leaf: plays one clip. The tree owns the AnimationTrack; the leaf only receives a weight.
local Animation = {}
Animation.__index = Animation

-- definition: { clip = 'Walk' | index | clip table, speed = 1, loop = true, order = 0,
--               mask = { BoneName = 1 }, retarget = {...} }
function Animation.new(definition)
    assert(definition.clip ~= nil, 'An Animation node needs a clip')
    return setmetatable({
        kind = 'Animation',
        definition = definition,
        loop = definition.loop ~= false,
        speed = definition.speed or 1,
        children = {},
    }, Animation)
end

function Animation:collect(list)
    list[#list + 1] = self
end

function Animation:evaluate(weight, scale, context)
    context:add(self, weight, scale)
end

function Animation:restart()
    local track = self.track
    if track then
        track.timePosition, track._loops = 0, 0
        if track.state ~= 'Playing' then
            track:resume()
        end
    end
end

function Animation:finished()
    local track = self.track
    return track ~= nil and not self.loop and track.state == 'Paused'
end

function Animation:duration()
    return self.track and self.track.clip.duration or 0
end

return Animation
