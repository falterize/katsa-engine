local Locomotion = require('../locomotion')

local Jump = {}

function Jump.enter(player)
    player.velocity[2] = player.settings.jumpPower
    player.grounded, player.air = false, true
    player.jumpTimer = player.settings.jumpGrace
    player.jumpSequence = player.jumpSequence + 1
end

function Jump.update(player, dt)
    Locomotion.air(player, dt)
    if player.velocity[2] <= 0 then
        return 'fall'
    end
end

return Jump
