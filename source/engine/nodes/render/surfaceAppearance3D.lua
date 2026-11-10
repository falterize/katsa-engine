local ipairs = require('../../math.array').ipairs
local Node = require('../core.baseNode')
local Tint = require('../../components.rendering.tint')

local C = Node.define('SurfaceAppearance3D', 'Node')
C.propertySchema = {
    layerGroup = {},
    transparency = {
        min = 0,
        max = 1,
    },
    colorMap = {},
    normalMap = {},
    roughnessMap = {},
    metalnessMap = {},
    occlusionMap = {},
    emissionMap = {},
    color = {},
    roughness = { min = 0, max = 1 },
    metalness = { min = 0, max = 1 },
    normalScale = { min = 0 },
    occlusionStrength = { min = 0, max = 1 },
    emissionColor = {},
    emissionStrength = { min = 0 },
    pixelate = {},
    alphaMode = { options = { 'Inherit', 'Opaque', 'Mask', 'Blend' } },
    alphaCutoff = { min = 0, max = 1, visibleWhen = { key = 'alphaMode', equals = 'Mask' } },
}
require('../../components.media.image').describe(C)

function C.initialize(self)
    require('source.engine.components.media.image').initialize(self)
    for _, key in ipairs({
        'colorMap',
        'normalMap',
        'roughnessMap',
        'metalnessMap',
        'occlusionMap',
        'emissionMap',
    }) do
        self[key] = self[key] or ''
    end
    self.layerGroup = self.layerGroup or 'Default'
    Tint.normalize(self, 'SurfaceAppearance3D')
    self.emissionColor = self.emissionColor or { 1, 1, 1 }
    self.emissionStrength = self.emissionStrength or 0
    self.normalScale = self.normalScale or 1
    self.roughness = self.roughness or 0.6
    self.metalness = self.metalness or 0
    self.occlusionStrength = self.occlusionStrength or 1
    self.alphaMode = self.alphaMode or 'Inherit'
    self.alphaCutoff = self.alphaCutoff or 0.5
    self.pixelate = self.pixelate == true
    self.enabled = self.enabled ~= false
end

function C.mount(world, properties, parent)
    assert(parent and parent:isA('Mesh3D'), 'SurfaceAppearance3D belongs directly to Mesh3D')
    local node = Node.new('SurfaceAppearance3D', properties, parent)
    node._world = world
    return node
end

return C
