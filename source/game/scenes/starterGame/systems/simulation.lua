local Simulation = {}
Simulation.__index = Simulation

function Simulation.create(state)
    return setmetatable({ state = state }, Simulation)
end

function Simulation:update3D(dt)
    local state = self.state
    if state.preferences.rotationEnabled then
        state.cube.rotation[2] = (state.cube.rotation[2] + dt * 30) % 360
    end
    if state.scene.physics then
        state.scene.physics:update(dt)
    end
    state.scene.world:updateNodes(dt)
end

return Simulation
