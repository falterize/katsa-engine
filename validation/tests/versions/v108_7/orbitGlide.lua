-- The multiplayerCars camera glides between the on-foot and car views instead of cutting.
local Orbit = require('source.game.scenes.multiplayerCars.scripts.cameras.orbit')

local Module = {}

function Module.run(self)
    local camera = { position = { 0, 0, 0 }, rotation = { 0, 0, 0 }, referenceHeight = 720 }
    local orbit = Orbit.new({ physics = nil }, camera)
    orbit:follow(0.016, nil, 0)
    orbit:update(0, 1, 0)
    local walk = { camera.position[1], camera.position[2], camera.position[3] }
    orbit:setMode('car', 90)
    orbit:follow(0.016, 90, 0)
    orbit:update(20, 1, 0)
    local gap = math.abs(camera.position[1] - walk[1]) + math.abs(camera.position[3] - walk[3])
    self:check(gap < 1, 'the first frame after switching to the car view has barely moved')
    for _ = 1, 60 do
        orbit:follow(0.016, 90, 0)
        orbit:update(20, 1, 0)
    end
    local x = camera.position[1]
    orbit:setMode('car', 90) -- no change, no new glide
    orbit:follow(0.016, 90, 0)
    orbit:update(20, 1, 0)
    self:check(orbit.transition == nil and math.abs(camera.position[1] - x) < 0.5, 'the glide ends at the car view')
end

return Module
