local Simulation = {}
Simulation.__index = Simulation

function Simulation.create(state)
    return setmetatable({ state = state }, Simulation)
end

function Simulation:update3D(dt)
    local state = self.state
    if state.update then
        state:update(dt)
    else
        state.scene.world:updateNodes(dt)
    end
end

return Simulation
