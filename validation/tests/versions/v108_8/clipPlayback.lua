-- AnimationTrack ranges and loop modes, and the Animation node settings that use them.
local Class = require('source.engine.nodes').getClass('AnimationTrack')
local Animation = require('source.engine.animation.tree.nodes.animation')

local Module = {}

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-4)
end

local function track(settings)
    local result = setmetatable({
        clip = { duration = 2, markers = {} },
        looped = true,
        speed = 1,
        weight = 1,
        order = 0,
        timePosition = 0,
        state = 'Playing',
        emit = function() end,
    }, { __index = Class })
    for key, value in pairs(settings or {}) do
        result[key] = value
    end
    return result
end

function Module.run(tester)
    local ranged = track({ startTime = 0.5, endTime = 1.5, timePosition = 1.4 })
    ranged:advance(0.3)
    tester:check(near(ranged.timePosition, 0.7), 'A looped track wraps inside its start and end time')

    local bouncing = track({ loopMode = 'PingPong', timePosition = 1.8 })
    bouncing:advance(0.4)
    tester:check(near(bouncing.timePosition, 1.8), 'PingPong turns around at the end of the clip')
    bouncing:advance(0.5)
    tester:check(near(bouncing.timePosition, 1.3), 'PingPong then plays backward')

    local once = track({ looped = false, startTime = 0.5, endTime = 1, timePosition = 0.9 })
    once:advance(1)
    tester:check(near(once.timePosition, 1) and once.state == 'Paused', 'A one-shot track stops at its end time')

    local leaf = Animation.new({ clip = 'Walk', playMode = 'Backward', stretch = 2, startTime = 0.5, endTime = 1.5 })
    leaf.track = track({ speed = leaf.speed, startTime = 0.5, endTime = 1.5 })
    tester:check(leaf.speed == -2, 'Animation playMode Backward with a stretch gives a negative speed')
    leaf:restart()
    tester:check(near(leaf.track.timePosition, 1.5) and near(leaf:phase(), 1), 'A backward clip starts at the end of its part')
    leaf:setPhase(0.25)
    tester:check(near(leaf.track.timePosition, 0.75) and near(leaf:remaining(), 0.125), 'Phase and remaining time follow the part and the direction')
end

return Module
