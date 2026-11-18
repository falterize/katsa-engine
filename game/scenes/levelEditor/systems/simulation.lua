local Simulation = {}
Simulation.__index = Simulation

function Simulation.create(state)
    return setmetatable({ state = state }, Simulation)
end

function Simulation:update3D(dt)
    self.state:update(dt)
end

return Simulation
