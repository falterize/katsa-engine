local Simulation = {}
Simulation.__index = Simulation

function Simulation.create(state)
    return setmetatable({ state = state }, Simulation)
end

function Simulation:update3D(dt)
    local state = self.state
    -- Install only while this system runs; disabling it freezes the FSM and solver.
    if not self.beforeStep then
        self.beforeStep = function(_, step)
            state.player:step(step)
        end
        state.scene.physics.beforeStep = self.beforeStep
    end
    state.scene.physics:update(dt)
    state.animation:update(dt)
    state.scene.world:updateNodes(dt)
    state.orbit:update()
end

function Simulation:release()
    self.state.scene.physics.beforeStep = nil
end

return Simulation
