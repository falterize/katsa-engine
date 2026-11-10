local Array = require('../../math.array')
local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Node = require('../core.baseNode')

local C = Node.define('ParticleEmitter3D', 'Node3D')
local Definition = require('../../particles.emitterDefinition')
local defaults, enums = Definition.defaults, Definition.enums
C.defaults = defaults

C.propertySchema = {
    pixelate = {
        get = function(node)
            return require('source.engine.components.image').pixelate(node, node._world.environment)
        end,
    },
    adornee = {},
    supportStatus = { readOnly = true },
}
for key, value in pairs(defaults) do
    C.propertySchema[key] = {
        options = enums[key],
    }
end
for _, key in ipairs({
    'attractionPoint',
    'attractionStrength',
    'attractionRange',
    'attractionSoftening',
}) do
    C.propertySchema[key].visibleWhen = { key = 'attractionEnabled', equals = true }
end
for _, key in ipairs({ 'atlasGrid', 'atlasFPS', 'atlasLoop' }) do
    C.propertySchema[key].visibleWhen = { key = 'atlasEnabled', equals = true }
end
for _, key in ipairs({ 'collisionGroup', 'restitution', 'collisionFriction', 'collisionResponse' }) do
    C.propertySchema[key].visibleWhen = { key = 'collisionEnabled', equals = true }
end
for _, key in ipairs({ 'axisRight', 'axisUp' }) do
    C.propertySchema[key].visibleWhen = { key = 'orientation', equals = 'Axes' }
end
C.propertySchema.surfaceOnly.visibleWhen =
    { key = 'shape', oneOf = { 'Box', 'Sphere', 'Disc', 'Cylinder' } }
C.propertySchema.shapeSize.visibleWhen =
    { key = 'shape', oneOf = { 'Box', 'Sphere', 'Disc', 'Cylinder' } }
C.propertySchema.gravity.visibleWhen = { key = 'useWorldGravity', equals = false }
require('../../components.image').describe(C)
require('../../components.lighting').describe(C)
require('../../components.brightness').describe(C)
require('../../components.shadowing').describe(C, { extra = { 'shadowMaxParticles' } })
C.propertySchema.atlasAnimation = { visibleWhen = { key = 'imageMode', equals = 'XML' } }
C.propertySchema.atlasGrid.visibleWhen = function(node)
    return node.imageMode == 'Atlas' or node.atlasEnabled and node.imageMode == 'Decal'
end
C.propertySchema.liveCount.readOnly = true
for _, key in ipairs({ 'lifetime', 'speed', 'startSize', 'startRotation', 'angularSpeed' }) do
    C.propertySchema[key].labels = { 'Min', 'Max' }
end
for _, key in ipairs({ 'sizeCurve', 'transparencyCurve', 'startColor', 'midColor', 'endColor' }) do
    C.propertySchema[key] = nil
end

function C.initialize(self)
    require('source.engine.components.lighting').normalize(self, 0)
    local legacyQuality = self.quality
    if legacyQuality then
        local limit = ({ Low = 128, Medium = 512, High = 2048 })[legacyQuality]
        if limit then
            self.maxParticles = math.min(self.maxParticles or 512, limit)
        end
        if legacyQuality == 'Low' then
            self.rate = (self.rate or 30) * 0.5
        end
    end
    self.quality = nil
    self.enabled = self.enabled ~= false
    self.visible = self.visible ~= false
    for key, value in pairs(defaults) do
        if self[key] == nil then
            self[key] = Array.is(value) and { unpack(value) } or value
        end
    end
    require('source.engine.particles.image').initialize(self)
    self._requestedAdornee = rawget(self, 'adornee')
    rawset(self, 'adornee', nil)
    self.particles, self.pool = {}, {}
    self.random = katsa.math.newRandomGenerator(self.seed)
    self.emission = 0
end

function C.mount(world, properties, parent)
    local node = Node.new('ParticleEmitter3D', properties, parent)
    node._world = world
    if not world.particles then
        world.particles = require('source.engine.particles.system').new(world)
    end
    require('source.engine.world.surfaces.support').initialize(node, node._requestedAdornee)
    node._requestedAdornee = nil
    world.particles:add(node)
    node.lifetimeRamp = world:create('Ramp', { name = 'LifetimeRamp', bindings = {} }, node)
    require('source.engine.particles.lifetime').configure(node, properties.lifetimeBindings)
    node.lifetimeBindings = nil
    node:onDestroy(function()
        world.particles:remove(node)
    end)
    return node
end

function C:setAdornee(node)
    return require('source.engine.world.surfaces.support').set(self, node)
end

function C:emissionMatrix(render)
    local Support = require('source.engine.world.surfaces.support')
    local reference = Support.resolve(self)
    if not reference then
        return self._emissionMatrix or require('source.engine.math.math3d').identity()
    end
    local M = require('source.engine.math.math3d')
    self._emissionLocal = M.compose(self.position, self.rotation, self.scale, self._emissionLocal)
    self._emissionMatrix = M.multiply(
        Support.frame(self, reference, render),
        self._emissionLocal,
        self._emissionMatrix
    )
    return self._emissionMatrix
end

function C:getWorldMatrix()
    return self:emissionMatrix(false)
end

function C:getRenderWorldMatrix()
    return self:emissionMatrix(true)
end

function C:emit(count, ...)
    if type(count) == 'string' then
        return Node.emit(self, count, ...)
    end
    assert(not self.destroyed, 'Cannot emit from a destroyed ParticleEmitter3D')
    return self._world.particles:emit(self, count)
end

function C:clear()
    for i = #self.particles, 1, -1 do
        self.pool[#self.pool + 1] = self.particles[i]
        self.particles[i] = nil
    end
    self.liveCount = 0
end

function C:setSeed(seed)
    self.seed = seed
    self.random:setSeed(seed)
    self._seed = seed
end

return C
