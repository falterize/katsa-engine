-- Shared definition of Beam3D and Trail3D: image configuration (the common image component),
-- blending, lighting, shadows, layers and the ribbon ramp. Each node class only adds its own
-- geometry properties.
local Node = require('../core.baseNode')
local V = require('../../core.validate')

local Ribbon = {}

local Lighting = require('../../components.lighting')
local Shadowing = require('../../components.shadowing')
local RenderRange = require('../../components.renderRange')
local Brightness = require('../../components.brightness')

Ribbon.defaults = {
    color = { 1, 1, 1 },
    texture = 'assets/textures/internal/white.png',
    textureMode = 'Stretch',
    textureLength = 1,
    textureSpeed = 0,
    faceCamera = true,
    lightEmission = 0,
    brightness = 1,
    zOffset = 0,
    maxDistance = 0,
    atlasEnabled = false,
    atlasFPS = 12,
    atlasLoop = true,
    atlasAnimation = '',
}

for key, value in pairs(Shadowing.defaults) do
    Ribbon.defaults[key] = value
end

-- Declares schema entries (hints, options, conditional visibility) for a ribbon class.
function Ribbon.describe(class, extra)
    require('../../components.image').describe(class)
    local schema = class.propertySchema
    for key in pairs(Ribbon.defaults) do
        schema[key] = schema[key] or {}
    end
    schema.textureMode.options = { 'Stretch', 'Wrap', 'Static' }
    schema.textureMode.visibleWhen = { key = 'imageMode', oneOf = { 'Decal' } }
    schema.textureLength.visibleWhen = function(node)
        return node.imageMode == 'Decal' and node.textureMode ~= 'Stretch'
    end
    schema.lightEmission.min, schema.lightEmission.max = 0, 1
    require('../../components.lighting').describe(class)
    require('../../components.shadowing').describe(class)
    RenderRange.describe(class)
    Brightness.describe(class)
    for _, key in ipairs({ 'atlasFPS', 'atlasLoop' }) do
        schema[key].visibleWhen = { key = 'atlasEnabled', equals = true }
    end
    schema.atlasEnabled.visibleWhen = { key = 'imageMode', oneOf = { 'Decal', 'Atlas' } }
    schema.atlasAnimation.visibleWhen = { key = 'imageMode', equals = 'XML' }
    schema.atlasGrid.visibleWhen = function(node)
        return node.imageMode == 'Atlas' or node.atlasEnabled and node.imageMode == 'Decal'
    end
    schema.ribbonKind = {
        visibleWhen = function()
            return false
        end,
    }
    for key, descriptor in pairs(extra or {}) do
        schema[key] = descriptor
    end
end

-- `defaults` is the class table (shared ribbon defaults plus the node's own).
function Ribbon.initialize(node, kind, defaults)
    node.enabled = node.enabled ~= false
    node.visible = node.visible ~= false
    node.ribbonKind = kind
    Lighting.normalize(node, 0)
    for key, value in pairs(defaults) do
        if node[key] == nil then
            node[key] = type(value) == 'table' and { unpack(value) } or value
        end
    end
    require('source.engine.particles.image').initialize(node)
end

function Ribbon.validate(node)
    local name = node.ribbonKind
    V.vector(node.color, name .. '.color', 3)
    V.number(node.textureLength, name .. '.textureLength', 1e-4)
    V.number(node.lightEmission, name .. '.lightEmission', 0, 1)
    Brightness.check(node.brightness, name)
    RenderRange.normalize(node, 0)
    require('source.engine.components.shadowing').validate(node, name)
    assert(
        node.textureMode == 'Stretch' or node.textureMode == 'Wrap' or node.textureMode == 'Static',
        name .. '.textureMode must be Stretch, Wrap or Static'
    )
end

-- Registers the node with its world and creates the ribbon ramp child.
function Ribbon.mount(world, properties, parent, kind)
    -- Node.new reparents to its argument (World3D:create passes the Effects folder), so an authored
    -- `parent` property has to win here.
    local node = Node.new(kind, properties, rawget(properties, 'parent') or parent)
    node._world = world
    if not world.ribbons then
        world.ribbons = require('source.engine.ribbons.system').new(world)
    end
    Ribbon.validate(node)
    node._points = {}
    node._born = world.simulationTime or 0
    world.ribbons:add(node)
    node.lifetimeRamp = world:create('Ramp', { name = 'RibbonRamp', bindings = {} }, node)
    require('source.engine.ribbons.lifetime').configure(node, properties.rampBindings)
    node.rampBindings = nil
    node:onDestroy(function()
        world.ribbons:remove(node)
    end)
    return node
end

return Ribbon
