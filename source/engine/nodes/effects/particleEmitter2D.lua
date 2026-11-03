local Node = require('../core.baseNode')
local Source = require('./particleEmitter3D')
local Array = require('../../math.array')
local Class = Node.define('ParticleEmitter2D', 'Node2D')
Class.defaults, Class.propertySchema = {}, {}
local excluded = {
    castShadow = true,
    receiveShadow = true,
    shadowGroup = true,
    shadowMaxParticles = true,
    shadowAlphaCutoff = true,
}
for key, value in pairs(Source.defaults) do
    if not excluded[key] then
        Class.defaults[key] = Array.is(value) and { Array.unpack(value) } or value
        local schema = {}
        for name, setting in pairs(Source.propertySchema[key] or {}) do
            schema[name] = setting
        end
        schema.hint = 'ParticleEmitter2D ' .. key .. '; see the particle API guide.'
        Class.propertySchema[key] = schema
    end
end
for _, key in ipairs({
    'direction',
    'shapeSize',
    'acceleration',
    'gravity',
    'attractionPoint',
    'axisRight',
    'axisUp',
}) do
    Class.defaults[key] = { Source.defaults[key][1], Source.defaults[key][2] }
end
Class.defaults.speed, Class.defaults.startSize = { 40, 100 }, { 8, 16 }
Class.defaults.shapeSize, Class.defaults.maxDistance = { 32, 32 }, 0
Class.propertySchema.shape.options = { 'Point', 'Box', 'Disc', 'Line' }
Class.propertySchema.simulationSpace.hint = Source.propertySchema.simulationSpace.hint
Class.propertySchema.liveCount.readOnly = true
Class.propertySchema.adornee = {
    kind = 'node',
    nodeClass = 'Node2D',
    hint = 'Optional emission support in the same World2D; ownership follows Parent.',
}

function Class.initialize(self)
    require('source.engine.components.lighting').normalize(self, 0)
    for key, value in pairs(Class.defaults) do
        if self[key] == nil then
            self[key] = Array.is(value) and { Array.unpack(value) } or value
        end
    end
    require('source.engine.particles.image').initialize(self)
    self.particles, self.pool, self.emission = {}, {}, 0
    self.random = katsa.math.newRandomGenerator(self.seed)
end

function Class.mount(ui, properties, parent)
    local node = Node.getClass('Node2D').mount(ui, properties, parent)
    ui = node._plane
    ui.particles = ui.particles or require('source.engine.particles.system').new(ui, 2)
    node._particleSystem = ui.particles
    ui.particles:add(node)
    node.lifetimeRamp = ui:create('Ramp', { name = 'LifetimeRamp', bindings = {} }, node)
    require('source.engine.particles.lifetime').configure(node, properties.lifetimeBindings)
    node.lifetimeBindings = nil
    node:onDestroy(function()
        ui.particles:remove(node)
    end)
    return node
end

function Class:getEffectiveOpacity()
    local opacity, node = 1, self
    while node and node ~= self._plane do
        if node.visible == false then
            return 0
        end
        opacity = opacity * (1 - (node.transparency or 0))
        node = node.parent
    end
    return opacity
end

function Class:emissionMatrix(render)
    local a, b, c, d, x, y
    local support = self.adornee
    self._adorneeLost = support and support.destroyed or false
    local key = render and '_particleRenderMatrix' or '_particleMatrix'
    if self._adorneeLost and self[key] then
        return self[key]
    end
    local transform = render and require('source.engine.ui.spatial.plane').transform
        or Node.getClass('Node2D').getWorldTransform
    if support and not self._adorneeLost then
        assert(support._plane == self._plane, 'Particle support must belong to the same World2D')
        local pa, pb, pc, pd, px, py = transform(support)
        local angle, scale = math.rad(self.rotation), self.scale
        local co, si = math.cos(angle), math.sin(angle)
        local la, lb, lc, ld = co * scale[1], si * scale[1], -si * scale[2], co * scale[2]
        a, b, c, d = pa * la + pc * lb, pb * la + pd * lb, pa * lc + pc * ld, pb * lc + pd * ld
        x, y =
            px + pa * self.position[1] + pc * self.position[2],
            py + pb * self.position[1] + pd * self.position[2]
    else
        a, b, c, d, x, y = transform(self)
    end
    local m = self[key] or {}
    self[key] = m
    m[1], m[2], m[3], m[4] = a, c, 0, x
    m[5], m[6], m[7], m[8] = b, d, 0, y
    m[9], m[10], m[11], m[12] = 0, 0, 1, 0
    m[13], m[14], m[15], m[16] = 0, 0, 0, 1
    return m
end

function Class:getWorldMatrix()
    return self:emissionMatrix(false)
end

function Class:getRenderWorldMatrix()
    return self:emissionMatrix(true)
end
Class.clear, Class.setSeed = Source.clear, Source.setSeed
function Class:emit(count, ...)
    if type(count) == 'string' then
        return Node.emit(self, count, ...)
    end
    assert(not self.destroyed, 'Cannot emit from a destroyed ParticleEmitter2D')
    self:getWorldMatrix()
    return self._particleSystem:emit(self, count)
end
return Class
