local Clock = require('source.engine.world.clock')
local Simulation = {}
Simulation.__index = Simulation

function Simulation.create(state)
    return setmetatable({ state = state }, Simulation)
end

function Simulation:update2D(dt)
    local state, ui = self.state, self.state.scene.ui
    state.controller:update(Clock.delta(ui, dt))
    ui:updatePhysics(dt)
    if ui.currentCamera then
        ui.currentCamera:updateFollow()
    end
end

function Simulation:update3D(dt)
    self.state.scene.world:updateNodes(dt)
end

function Simulation:release()
    self.state.scene.ui.autoUpdatePhysics = false
end

return Simulation
