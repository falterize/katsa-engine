local Node = require('../core.baseNode')

local Class = Node.define('Mesh3D', 'Node3D')

Class.propertySchema = {
    maxBoneInfluences = {
        min = 1,
        max = 8,
        integer = true,
    },
    bonePaletteLimit = {
        min = 1,
        max = 32,
        integer = true,
    },
    effectiveBonePaletteLimit = {
        readOnly = true,
    },
    skinDrawCount = { readOnly = true },
}

require('../../components.illumination.lighting').describe(Class)
require('../../components.rendering.renderRange').describe(Class)
require('../../components.illumination.shadowing').describe(Class, { cutoff = false })

function Class.initialize(self)
    self.maxBoneInfluences = self.maxBoneInfluences or 8
    self.bonePaletteLimit = self.bonePaletteLimit or 32
    self.effectiveBonePaletteLimit = 0
    self.skinDrawCount = 0
end

function Class.mount(world, properties, parent)
    properties.parent = parent
    return world:addObject(properties)
end

-- Blend shapes (Blender Shape Keys). Names follow Godot's MeshInstance3D; indices are 1-based.
-- A shape is addressed by name or index. Imported models without morph targets report zero.
function Class:getBlendShapeCount()
    return self.blendShapes and self.blendShapes.count or 0
end

-- A new table { [1] = 'Smile', [2] = 'Wide' }: index to shape name, in glTF target order.
function Class:getBlendShapes()
    local list = {}
    if self.blendShapes then
        for index, name in ipairs(self.blendShapes.names) do
            list[index] = name
        end
    end
    return list
end

function Class:getBlendShapeName(index)
    return self.blendShapes and self.blendShapes.names[index]
end

-- Returns the 1-based index of the shape called `name`, or nil.
function Class:findBlendShapeByName(name)
    return self.blendShapes and self.blendShapes:resolve(name)
end

function Class:getBlendShapeValue(shape)
    local state = self.blendShapes
    local index = state and state:resolve(shape)
    return index and state.values[index]
end

function Class:setBlendShapeValue(shape, value)
    assert(self.blendShapes, 'Mesh3D has no blend shapes')
    self.blendShapes:set(shape, value)
end

function Class:getCollisionPoints(body, options)
    return require('source.engine.physics.3d.pointCollider').extract(self, body, options)
end

return Class
