local Locomotion = require('../locomotion')

local Walk = {}

function Walk.enter(player)
    player.air = false
end

function Walk.update(player, dt)
    Locomotion.ground(player, dt, player.settings.walkSpeed, 2.5, true, false)
    local nextState = Locomotion.transition(player)
    if nextState then
        return nextState
    elseif not player:moving() then
        return 'idle'
    elseif player.input.sprint then
        return 'run'
    end
end

return Walk
