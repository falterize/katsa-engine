local Game = require('source.game.runtime.game')

local Tests = {}

local function frames(manager, count, each)
    for _ = 1, count do
        manager:update(1 / 60)
        if each then
            each()
        end
    end
end

-- Counts rendered frames in which a value visibly changes while the world is slowed.
local function changingFrames(samples, epsilon)
    local changed = 0
    for i = 2, #samples do
        if math.abs(samples[i] - samples[i - 1]) > epsilon then
            changed = changed + 1
        end
    end
    return changed, #samples - 1
end

function Tests.stareShooter(tester, backend)
    local manager = tester.manager
    local scene = assert(manager:switch(Game.new, 'stareShooter', { physicsBackend = backend }))
    local state = scene.demo
    local player = state.player
    scene.input.captureMouse = false
    scene.input.playing = function()
        return true
    end
    frames(manager, 30)
    scene.world.root.timeScale = 0.1
    scene.input.actions.keys.d = true
    local yaw = {}
    frames(manager, 120, function()
        yaw[#yaw + 1] = player.model.root.rotation[2]
    end)
    local changed, total = changingFrames(yaw, 1e-6)
    tester:check(
        changed >= total * 0.9,
        backend
            .. ': visual yaw changes on at least 90% of frames at TimeScale 0.1 ('
            .. changed
            .. '/'
            .. total
            .. ')'
    )
    scene.input.actions.keys.d = nil
    scene.world.root.timeScale = 1
end

function Tests.run(tester)
    for _, backend in ipairs({ 'jolt', 'oimo' }) do
        Tests.stareShooter(tester, backend)
    end
end

return Tests
