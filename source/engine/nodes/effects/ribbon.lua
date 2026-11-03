-- Shared definition of Beam3D and Trail3D: image configuration (the common image component),
-- blending, lighting, shadows, layers and the ribbon ramp. Each node class only adds its own
-- geometry properties.
local Node = require('../core.baseNode')
local V = require('../../core.validate')

local Ribbon = {}

Ribbon.defaults = {
    color = { 1, 1, 1 },
    texture = 'assets/textures/internal/white.png',
    textureMode = 'Stretch',
    textureLength = 1,
    textureSpeed = 0,
    faceCamera = true,
    lightEmission = 0,
    lightInfluence = 0,
    brightness = 1,
    zOffset = 0,
    maxDistance = 0,
    castShadow = false,
    receiveShadow = false,
    shadowGroup = 'Default',
    shadowAlphaCutoff = 0.1,
    atlasEnabled = false,
    atlasFPS = 12,
    atlasLoop = true,
    atlasAnimation = '',
}

local hints = {
    texture = 'Image path, for example scene://assets/textures/trail.png. Empty or missing files '
        .. 'render the diagnostic checker. Use pixelate for nearest filtering.',
    textureMode = 'Stretch: the image covers the whole ribbon. Wrap: it repeats every '
        .. 'textureLength units and moves with the ribbon. Static: it repeats in world space and '
        .. 'stays put while the ribbon moves. Tiles, Texture, Atlas and XML image modes always use '
        .. 'their own mapping.',
    textureLength = 'World units covered by one image repeat (Wrap and Static).',
    textureSpeed = 'Scroll speed of the image along the ribbon in repeats per second.',
    faceCamera = 'On: the ribbon always turns its width toward the camera. Off: a flat strip that '
        .. 'keeps the orientation of its attachments.',
    lightEmission = '0 blends normally, 1 adds the colour to the scene (glow). Values between mix both.',
    lightInfluence = '0: unlit, the ribbon shows its own colour. 1: fully lit by the scene lights.',
    brightness = 'Colour multiplier applied after lighting.',
    zOffset = 'World units added to the sorting depth. Positive values draw the ribbon earlier '
        .. '(behind other transparent objects).',
    maxDistance = 'Render cutoff distance in world units; 0 disables it.',
    castShadow = 'Adds the ribbon to the shadow maps as an alpha tested strip.',
    receiveShadow = 'Shadows from other objects darken the ribbon (needs lightInfluence above 0).',
    shadowGroup = 'Layer group used to decide which lights this ribbon casts into and receives from.',
    shadowAlphaCutoff = 'Ribbons that are more transparent than this cast no shadow.',
}

-- Declares schema entries (hints, options, conditional visibility) for a ribbon class.
function Ribbon.describe(class, extra)
    require('../../components.image').describe(class)
    local schema = class.propertySchema
    for key in pairs(Ribbon.defaults) do
        schema[key] = schema[key] or {}
        schema[key].hint = hints[key]
    end
    schema.textureMode.options = { 'Stretch', 'Wrap', 'Static' }
    schema.textureMode.visibleWhen = { key = 'imageMode', oneOf = { 'Decal' } }
    schema.textureLength.visibleWhen = function(node)
        return node.imageMode == 'Decal' and node.textureMode ~= 'Stretch'
    end
    schema.lightEmission.min, schema.lightEmission.max = 0, 1
    schema.lightInfluence.min, schema.lightInfluence.max = 0, 1
    schema.receiveShadow.visibleWhen = function(node)
        return node.lightInfluence > 0
    end
    schema.shadowGroup.visibleWhen = function(node)
        return node.castShadow or node.receiveShadow
    end
    schema.shadowAlphaCutoff.visibleWhen = { key = 'castShadow', equals = true }
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
    V.number(node.lightInfluence, name .. '.lightInfluence', 0, 1)
    V.number(node.brightness, name .. '.brightness', 0)
    V.number(node.maxDistance, name .. '.maxDistance', 0)
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
