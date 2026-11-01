local Game = require('source.game.runtime.game')

local Tests = {}

-- Sums every bone channel so any visible pose change alters the value.
local function poseSignature(model)
    local sum = 0
    for _, node in ipairs(model.nodes) do
        for _, path in ipairs({ 'translation', 'rotation', 'scale' }) do
            local value = node[path]
            for i = 1, #value do
                sum = sum + value[i] * (i * 0.37 + 1)
            end
        end
    end
    return sum
end

function Tests.run(tester)
    local manager = tester.manager
    for _, timeScale in ipairs({ 1, 0.5, 0.1 }) do
        local scene = assert(manager:switch(Game.new, 'stareShooter', { physicsBackend = 'jolt' }))
        local player = scene.demo.player
        scene.input.captureMouse = false
        scene.input.playing = function()
            return true
        end
        for _ = 1, 30 do
            manager:update(1 / 60)
        end
        scene.world.root.timeScale = timeScale
        scene.input.actions.keys.d = true
        for _ = 1, 20 do
            manager:update(1 / 60)
        end
        local previous, changed, total = poseSignature(player.model), 0, 120
        for _ = 1, total do
            manager:update(1 / 60)
            local current = poseSignature(player.model)
            if math.abs(current - previous) > 1e-7 then
                changed = changed + 1
            end
            previous = current
        end
        tester:check(
            changed >= total * 0.9,
            ('Skeleton pose changes on every rendered frame at TimeScale %s (%d/%d)'):format(
                timeScale,
                changed,
                total
            )
        )
        scene.input.actions.keys.d = nil
        scene.world.root.timeScale = 1
    end
end

return Tests
