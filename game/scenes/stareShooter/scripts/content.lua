local Level = require('./builders.level')
local Builder = require('game.characters.playerBody')
local Destare = require('./builders.destare')
local Orbit = require('game.characters.orbit')
local Input = require('game.characters.thirdPersonInput')
local Animation = require('game.characters.animation')
local Ragdoll = require('./behaviors.ragdoll')

local Content = {}
Content.__index = Content

function Content.new(scene)
    scene:createPhysics3D({
        unitsPerMeter = 1,
        gravity = { 0, -24.5, 0 },
        fixedDelta = 1 / 60,
        interpolate = true,
    })
    Level.create(scene)
    local player = Builder.create(scene)
    scene.destare = Destare.create(scene)
    local orbit = Orbit.new(scene, player)
    -- Third person by default; the wheel still zooms into first person.
    orbit.distance = 8
    scene.character = player
    scene.input = Input.new(scene, player, orbit)
    local ragdoll = Ragdoll.new(scene, player)
    scene.input.keyHandler = function(key)
        if key == 'r' then
            ragdoll:toggle()
            return true
        end
        if key == 'f6' then
            scene.demo.retro.enabled = not scene.demo.retro.enabled
            return true
        end
    end
    orbit:update()
    return setmetatable(
        {
            scene = scene,
            player = player,
            orbit = orbit,
            animation = Animation.new(player),
            ragdoll = ragdoll,
        },
        Content
    )
end

function Content:release()
    self.scene.physics.beforeStep = nil
    katsa.mouse.setRelativeMode(false)
end

return Content
