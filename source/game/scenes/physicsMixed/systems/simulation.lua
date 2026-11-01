local Simulation = {}
Simulation.__index = Simulation

function Simulation.create(state)
    return setmetatable({ state = state }, Simulation)
end

function Simulation:update3D(dt)
    local scene = self.state.scene
    if scene.physics then
        scene.physics:update(dt)
    end
    scene.world:updateNodes(dt)
end

function Simulation:update2D(dt)
    local ui = self.state.scene.ui
    ui:updatePhysics(dt)
    if ui.currentCamera then
        ui.currentCamera:updateFollow()
    end
end

function Simulation:release()
    self.state.scene.ui.autoUpdatePhysics = false
end

return Simulation
