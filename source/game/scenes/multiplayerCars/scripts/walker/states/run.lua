local Locomotion = require('scene.scripts.walker.locomotion')

local Run = {}

function Run.enter(player)
    player.air = false
end

function Run.update(player, dt)
    Locomotion.ground(player, dt, player.settings.runSpeed, 3.5, true, false)
    local nextState = Locomotion.transition(player)
    if nextState then
        return nextState
    elseif not player:moving() then
        return 'idle'
    elseif not player.input.sprint then
        return 'walk'
    end
end

return Run
