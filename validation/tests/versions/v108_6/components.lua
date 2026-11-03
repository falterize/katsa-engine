-- Layer groups and render range are shared components used by every node kind.
local Layering = require('source.engine.components.layering')
local RenderRange = require('source.engine.components.renderRange')
local Brightness = require('source.engine.components.brightness')
local Tables = require('source.engine.core.tables')
local Math = require('source.engine.math.math3d')
local World = require('source.engine.world.world')

local Module = {}

function Module.run(self)
    self:check(Layering.sees({ layers = 3 }, { layers = 2 }), 'a camera mask that contains the bit sees the node')
    self:check(not Layering.sees({ layers = 1 }, { layers = 2 }), 'a camera mask without the bit does not see the node')
    self:check(Layering.sees({}, {}), 'defaults see each other')
    self:check(RenderRange.within(0, 1e12, 1), 'a zero range is unlimited')
    self:check(RenderRange.within(10, 120, 1), 'a sphere reaching into the range stays')
    self:check(not RenderRange.within(10, 130, 1), 'a sphere beyond the range is culled')

    local node = {}
    Brightness.normalize(node, 2, 'Test')
    self:check(node.brightness == 2, 'brightness takes the class default')
    self:check(not pcall(Brightness.check, -1, 'Test'), 'negative brightness is rejected')
    local source = { a = { 1, { b = 2 } } }
    local copy = Tables.copy(source)
    self:check(copy.a ~= source.a and copy.a[2].b == 2, 'Tables.copy is deep')
    local _, _, _, length = Math.unit(0, 3, 4)
    self:check(length == 5 and select(4, Math.unit(0, 0, 0)) == 0, 'Math.unit returns the length and survives zero')
    self:check(Math.clamp(5, 0, 1) == 1 and Math.clamp(-5, 0, 1) == 0, 'Math.clamp bounds a value')

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
