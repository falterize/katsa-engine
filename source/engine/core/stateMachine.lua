-- Small finite state machine shared by gameplay controllers. A state is a table with optional
-- `enter(owner, previous)` and `exit(owner, next)` and a required `update(owner, dt)` that returns
-- the name of the next state, or nothing to stay.
local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(owner, states, initial)
    local self = setmetatable({ owner = owner, states = states }, StateMachine)
    self:change(initial or 'idle')
    return self
end

function StateMachine:change(name)
    if self.name == name then
        return
    end
    local nextState = assert(self.states[name], 'Unknown state: ' .. tostring(name))
    local previous = self.name
    if self.state and self.state.exit then
        self.state.exit(self.owner, name)
    end
    self.name, self.state = name, nextState
    if nextState.enter then
        nextState.enter(self.owner, previous)
    end
end

function StateMachine:update(dt)
    local nextState = self.state.update(self.owner, dt)
    if nextState then
        self:change(nextState)
    end
end

return StateMachine
