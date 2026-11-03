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
    adornee = {
        hint = 'Independent emission support. None uses spatial Parent. Ownership and cleanup '
            .. 'still follow Parent.',
    },
    supportStatus = { readOnly = true },
}
for key, value in pairs(defaults) do
    C.propertySchema[key] = {
        options = enums[key],
        hint = 'ParticleEmitter3D ' .. key .. '; see the particle API guide.',
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
C.propertySchema.useWorldGravity.hint =
    'Use Physics.gravity when present; otherwise use the emitter gravity vector. Disable to '
        .. 'author an independent field.'
require('../../components.image').describe(C)
require('../../components.shadowing').describe(C, { 'shadowMaxParticles' })
C.propertySchema.atlasAnimation = { visibleWhen = { key = 'imageMode', equals = 'XML' } }
C.propertySchema.atlasGrid.visibleWhen = function(node)
    return node.imageMode == 'Atlas' or node.atlasEnabled and node.imageMode == 'Decal'
end
C.propertySchema.liveCount.readOnly = true
for _, key in ipairs({ 'lifetime', 'speed', 'startSize', 'startRotation', 'angularSpeed' }) do
    C.propertySchema[key].labels = { 'Min', 'Max' }
end
local hints = {
    shadowMaxParticles = 'Most particles that are written into the shadow maps per frame.',
    rate = 'Births per second, controlled directly by Rate.',
    lifetime = 'Seconds: randomized Min / Max at birth.',
    speed = 'Local units per second: Min / Max at birth.',
    gravityScale = 'Dimensionless multiplier of the world-space gravity vector. 0 disables '
        .. 'gravity; negative values repel upward.',
    drag = 'Per-second velocity relaxation toward wind; 0 gives no wind drag.',
    attractionPoint = 'World-space target position, independent of emitter/parent rotation.',
    attractionStrength = 'Acceleration at the target in world units/second squared, softened '
        .. 'with distance.',
    attractionSoftening = 'Positive world-unit radius: acceleration is strength / (1 + '
        .. '(distance/radius)^2).',
    spread = 'Cone half-angle in degrees, 0 to 180.',
    startSize = 'Full quad width/height in world units at birth, before sizeCurve.',
    shapeSize = 'Full local X/Y/Z extents; cylinder/disc radii are half X/Z.',
    simulationSpace = 'Local (LockedOnPart): existing particles follow the emitter/attachment position, rotation and scale. World: existing particles stay in world space. Changes affect new births.',
    maxParticles = 'Birth cap, further limited by the shared MaxParticles budget. Existing '
        .. 'particles drain after lowering it.',
    liveCount = 'Current live particles. Runtime read-only.',
    disabledBehavior = 'Drain: stop automatic births and let particles finish; Clear: '
        .. 'immediately remove existing particles.',
    axisRight = 'Emitter-local plane axis. Both axes must be nonzero and independent.',
    axisUp = 'Emitter-local plane axis, orthogonalized to axisRight.',
    collisionEnabled = 'Optional point-segment physics raycasts, sharing a bounded update '
        .. 'budget. No rigid body per particle.',
    maxDistance = 'World-unit render cutoff per particle; 0 disables it. OffscreenBehavior '
        .. 'controls simulation outside the camera view.',
    offscreenBehavior = 'Pause stops simulation, births and collision queries outside the camera view. Simulate preserves continuous offscreen physics. Existing world-space particles also participate in visibility.',
}
for key, hint in pairs(hints) do
    C.propertySchema[key].hint = hint
end
for _, key in ipairs({ 'sizeCurve', 'transparencyCurve', 'startColor', 'midColor', 'endColor' }) do
    C.propertySchema[key] = nil
end

function C.initialize(self)
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
    require('source.engine.surfaces.support').initialize(node, node._requestedAdornee)
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
    return require('source.engine.surfaces.support').set(self, node)
end

function C:emissionMatrix(render)
    local Support = require('source.engine.surfaces.support')
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
