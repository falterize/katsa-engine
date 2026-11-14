-- Additive AnimationTracks on the real Animator pose mixer: translation adds the difference to the
-- first frame, rotation composes, a bone mask limits the bones, and the base pose is untouched.
local Class = require('source.engine.nodes').getClass('Animator')

local Module = {}

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-4)
end

local function bone(name)
    return {
        name = name,
        translation = { 0, 0, 0 },
        rotation = { 0, 0, 0, 1 },
        scale = { 1, 1, 1 },
        rest = { translation = { 0, 0, 0 }, rotation = { 0, 0, 0, 1 }, scale = { 1, 1, 1 } },
    }
end

local function track(nodes, channels, settings)
    local lookup = {}
    for node, paths in pairs(channels) do
        lookup[node] = {}
        for path, values in pairs(paths) do
            lookup[node][path] = { times = { { 0 }, { 1 } }, values = values, node = node, target = path }
        end
    end
    local result = {
        clip = { _lookup = lookup, channels = {}, markers = {}, duration = 1 },
        enabled = true,
        state = 'Playing',
        boneMask = {},
        order = 0,
        timePosition = 0,
        _blendWeight = 1,
        _buffers = {},
        advance = function() end,
    }
    for key, value in pairs(settings or {}) do
        result[key] = value
    end
    return result
end

function Module.run(tester)
    local spine, arm = bone('Spine'), bone('Arm')
    local model = { nodes = { spine, arm }, update = function() end }
    local animator = setmetatable({
        model = model,
        modifiers = {},
        controllers = {},
        tracks = {},
        poseRate = 60,
    }, { __index = Class })
    local still = { { 0, 0, 0 }, { 0, 0, 0 } }
    local base = track(nil, { [spine] = { translation = still }, [arm] = { translation = still } })
    local lift = track(nil, {
        [spine] = {
            translation = { { 0, 0, 0 }, { 0, 1, 0 } },
            rotation = { { 0, 0, 0, 1 }, { 0, 0, math.sin(math.pi / 4), math.cos(math.pi / 4) } },
        },
        [arm] = { translation = { { 0, 0, 0 }, { 0, 1, 0 } } },
    }, { additive = true, timePosition = 0.5, _blendWeight = 0.5 })
    animator.tracks = { base, lift }
    animator:update(1 / 60)
    tester:check(near(spine.translation[2], 0.25) and near(arm.translation[2], 0.25), 'An additive track adds weight times its difference to the first frame')
    tester:check(near(spine.rotation[3], math.sin(math.pi / 16), 0.01), 'An additive rotation composes by the weighted delta')
    lift.boneMask = { Arm = 1 }
    animator._poseWall = 1
    animator:update(1 / 60)
    tester:check(near(spine.translation[2], 0) and near(arm.translation[2], 0.25), 'An additive bone mask limits the bones')
    lift._blendWeight = 0
    animator._poseWall = 1
    animator:update(1 / 60)
    tester:check(near(arm.translation[2], 0), 'An additive track with no weight leaves the base pose')
end

return Module
