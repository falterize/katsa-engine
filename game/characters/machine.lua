-- The scene's state machine is the shared engine one, starting in 'idle'.
local StateMachine = require('source.engine.core.stateMachine')

local Machine = {}

function Machine.new(owner, states)
    return StateMachine.new(owner, states, 'idle')
end

return Machine
