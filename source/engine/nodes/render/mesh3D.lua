local Node = require('../core.baseNode')

local Class = Node.define('Mesh3D', 'Node3D')

Class.propertySchema = {
    maxBoneInfluences = {
        min = 1,
        max = 8,
        integer = true,
        hint = 'Strongest weights retained per vertex (1..8), then normalized. Imported data '
            .. 'stays intact.',
    },
    bonePaletteLimit = {
        min = 1,
        max = 32,
        integer = true,
        hint = 'Requested bones per draw (1..32). Triangles keep all required joints; smaller '
            .. 'palettes may add draws.',
    },
    effectiveBonePaletteLimit = {
        readOnly = true,
        hint = 'Largest palette used; may exceed the request to preserve an indivisible triangle.',
    },
    skinDrawCount = { readOnly = true, hint = 'Draw pieces after applying skin limits.' },
}

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

function Class:getCollisionPoints(body, options)
    return require('source.engine.physics.3d.pointCollider').extract(self, body, options)
end

return Class
