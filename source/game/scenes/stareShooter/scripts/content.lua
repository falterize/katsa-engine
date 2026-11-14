local Level = require('./builders.level')
local Builder = require('source.game.characters.playerBody')
local Destare = require('./builders.destare')
local Orbit = require('source.game.characters.orbit')
local Input = require('source.game.characters.thirdPersonInput')
local Animation = require('source.game.characters.animation')

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
    scene.destare = Destare.create(scene)
    local orbit = Orbit.new(scene, player)
    scene.character = player
    scene.input = Input.new(scene, player, orbit)
    scene.input.keyHandler = function(key)
        if key == 'f6' then
            scene.demo.retro.enabled = not scene.demo.retro.enabled
            return true
        end
    end
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
