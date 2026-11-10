-- A tilted car's model origin hangs below the chassis along the car's own up axis.
local Module = {}

function Module.run(self)
    local Math = require('source.engine.math.math3d')
    local CarAxes = require('source.game.scenes.multiplayerCars.scripts.game.carAxes')
    local orientation = require('source.game.scenes.multiplayerCars.scripts.shared.orientation')
    local level = CarAxes.up(40, 0, 0)
    self:check(
        math.abs(level[2] - 1) < 1e-9 and math.abs(level[1]) + math.abs(level[3]) < 1e-9,
        'a level car points straight up'
    )
    local worst = 0
    for _, pose in ipairs({ { 30, 25, 10 }, { 200, -35, 40 }, { 90, 15, -50 } }) do
        local euler = orientation(pose[1], pose[2], pose[3], {})
        local m = Math.compose({ 0, 0, 0 }, euler, { 1, 1, 1 }, {})
        local up = CarAxes.up(pose[1], pose[2], pose[3])
        worst = math.max(
            worst,
            math.abs(up[1] - m[2]),
            math.abs(up[2] - m[6]),
            math.abs(up[3] - m[10])
        )
    end
    self:check(worst < 1e-6, ('the up axis matches the rendered orientation (error %.1e)'):format(worst))
end

return Module
