local Locomotion = require('scene.scripts.fsm.locomotion')

local Idle = {}

function Idle.enter(player)
    player.air = false
end

function Idle.update(player, dt)
    Locomotion.ground(player, dt, 0, 0, false, false)
    return Locomotion.transition(player)
        or (player:moving() and (player.input.sprint and 'run' or 'walk'))
        or nil
end

return Idle
