-- Layer groups and render range are shared components used by every node kind.
local Layering = require('source.engine.components.layering')
local RenderRange = require('source.engine.components.renderRange')
local World = require('source.engine.world.world')

local Module = {}

function Module.run(self)
    self:check(Layering.sees({ layers = 3 }, { layers = 2 }), 'a camera mask that contains the bit sees the node')
    self:check(not Layering.sees({ layers = 1 }, { layers = 2 }), 'a camera mask without the bit does not see the node')
    self:check(Layering.sees({}, {}), 'defaults see each other')
    self:check(RenderRange.within(0, 1e12, 1), 'a zero range is unlimited')
    self:check(RenderRange.within(10, 120, 1), 'a sphere reaching into the range stays')
    self:check(not RenderRange.within(10, 130, 1), 'a sphere beyond the range is culled')

    local world = World.new(self.manager.resources:scope())
    world:addLayer('Hidden')
    local mesh = world:create('Mesh3D', { name = 'M', size = { 1, 1, 1 } })
    local beam = world:create('Beam3D', {})
    local emitter = world:create('ParticleEmitter3D', {})
    for _, node in ipairs({ mesh, beam, emitter }) do
        world:resolveLayerGroup(node)
        self:check(node.layerGroup == 'Default' and node.layers == 1, node.className .. ' has a layer group')
    end
    self:check(mesh.maxDistance == 0 and beam.maxDistance == 0, 'meshes and ribbons share the maxDistance default')
end

return Module
