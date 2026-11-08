-- Wheels roll in the direction of travel.
local Module = {}

function Module.run(self)
    local CarView = require('source.game.scenes.multiplayerCars.scripts.view.carView')
    local Math = require('source.engine.math.math3d')
    local rotation = CarView.wheelRotation(30, 0)
    local m = Math.compose({ 0, 0, 0 }, rotation, { 1, 1, 1 }, {})
    -- The tire top (0, r, 0) must move toward +z (forward) when spin grows with positive speed.
    local topZ = m[10] -- row-major: column 2 holds the image of (0, 1, 0)
    self:check(topZ > 0.1, 'Forward speed rolls the top of a wheel toward the front')
    local steered = CarView.wheelRotation(0, 20)
    self:check(steered[2] == -20 and steered[1] == 0, 'Steering turns the wheel opposite to engine yaw')
end

return Module
