local Level = require('./builders.level')
local Builder = require('./builders.player')
local Orbit = require('./cameras.orbit')
local Input = require('./controller.input')
local Animation = require('./animation.controller')

local Content = {}
Content.__index = Content

function Content.new(scene)
    scene:createPhysics({
        unitsPerMeter = 1,
        gravity = { 0, -24.5, 0 },
        fixedDelta = 1 / 60,
        interpolate = true,
    })
    Level.create(scene)
    local player = Builder.create(scene)
    local orbit = Orbit.new(scene, player)
    scene.character = player
    scene.input = Input.new(scene, player, orbit)
    orbit:update()
    return setmetatable(
        { scene = scene, player = player, orbit = orbit, animation = Animation.new(player) },
        Content
    )
end

function Content:release()
    self.scene.physics.beforeStep = nil
    katsa.mouse.setRelativeMode(false)
end

return Content
