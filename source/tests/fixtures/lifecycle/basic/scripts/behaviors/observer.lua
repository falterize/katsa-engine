local Observer = {}
Observer.__index = Observer
function Observer.create(state, name)
    local self = setmetatable({ state = state, name = name, starts = 0, ticks = 0 }, Observer)
    state[name] = self
    return self
end

function Observer:start()
    self.starts = self.starts + 1
end

function Observer:update(dt)
    self.ticks = self.ticks + 1
    self.state.events[#self.state.events + 1] = self.name
end

function Observer:update3D(dt)
    self.three = (self.three or 0) + 1
end

function Observer:update2D(dt, realDt)
    self.two = (self.two or 0) + 1
    self.uiDelta = realDt
end

function Observer:release()
    self.released = true
end
return Observer
