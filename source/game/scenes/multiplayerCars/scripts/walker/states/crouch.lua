local Locomotion = require('../locomotion')

local Crouch = {}

function Crouch.enter(player)
    player.targetHeight = player.settings.crouchingHeight
    player.air = false
end

function Crouch.exit(player)
    player.targetHeight = player.settings.standingHeight
end

function Crouch.update(player, dt)
    Locomotion.ground(
        player,
        dt,
        player.settings.walkSpeed * player.settings.crouchSpeedFactor,
        1.5,
        true,
        true
    )
    if not player.grounded then
        return 'fall'
    elseif not player.input.crouch then
        return player:moving() and 'walk' or 'idle'
    end
end

return Crouch
