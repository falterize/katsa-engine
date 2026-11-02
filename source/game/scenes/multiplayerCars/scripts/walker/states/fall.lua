local Locomotion = require('scene.scripts.walker.locomotion')
local Math = require('scene.scripts.walker.math')

local Fall = {}

function Fall.enter(player)
    player.air = true
end

function Fall.update(player, dt)
    Locomotion.air(player, dt)
    player.crouchBlend = Math.approach(player.crouchBlend, 0, player.settings.blendSpeed * dt)
    if player.grounded then
        return player.input.crouch and 'crouch' or (player:moving() and 'walk' or 'idle')
    end
end

return Fall
