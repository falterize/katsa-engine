local Machine = {}
Machine.__index = Machine

function Machine.new(owner, states)
    local self = setmetatable({ owner = owner, states = states }, Machine)
    self:change('idle')
    return self
end

function Machine:change(name)
    if self.name == name then
        return
    end
    local nextState = assert(self.states[name], 'Unknown player state: ' .. tostring(name))
    if self.state and self.state.exit then
        self.state.exit(self.owner)
    end
    self.name, self.state = name, nextState
    if nextState.enter then
        nextState.enter(self.owner)
    end
end

function Machine:update(dt)
    local nextState = self.state.update(self.owner, dt)
    if nextState then
        self:change(nextState)
    end
end

return Machine
