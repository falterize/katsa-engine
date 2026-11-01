local Simulation = {}
Simulation.__index = Simulation

function Simulation.create(lab)
    return setmetatable({ lab = lab }, Simulation)
end

function Simulation:update3D(dt)
    local lab = self.lab
    lab.scene.physics:update(dt)
    lab.scene.world:updateNodes(dt)
    if lab.info then
        lab.info.text = string.format(
            'Wave: %s / Order %d / Speed %.2f / Weight %.2f\n10 attachment constraints; rolling spheres and live motors.',
            lab.tracks.wave.state,
            lab.tracks.wave.order,
            lab.tracks.wave.speed,
            lab.tracks.wave._blendWeight
        )
    end
end

return Simulation
