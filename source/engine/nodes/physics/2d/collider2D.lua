local Node = require('source.engine.nodes.core.baseNode')
local Spatial = require('source.engine.nodes.spatial.node2D')

local Collider2D = Node.define('Collider2D', 'Node2D')
Collider2D.propertySchema = {
    image = {},
    collisionLevel = { options = { 'Simple', 'Convex', 'Detailed' } },
    imageResolution = { min = 1, max = 2048, integer = true },
    alphaThreshold = { min = 0, max = 1 },
    maxFixtures = { min = 1, max = 16384, integer = true },
    points = {},
    vertices = {},
    shape = { options = { 'Box', 'Circle', 'Polygon', 'Image', 'Edge', 'Chain' } },
    radius = { min = 0.001 },
    loop = {},
    density = { min = 0 },
    friction = { min = 0 },
    restitution = { min = 0 },
    isTrigger = {},
    enabled = {},
}

function Collider2D.initialize(self)
    self.shape = self.shape or 'Box'
    self.collisionLevel = self.collisionLevel or 'Simple'
    self.imageResolution = self.imageResolution or 128
    self.alphaThreshold = self.alphaThreshold or 0.5
    self.maxFixtures = self.maxFixtures or 1024
end

function Collider2D.mount(context, properties, parent)
    assert(parent and parent:isA('Body2D'), 'Collider2D requires a Body2D parent')
    return Spatial.mount(context, properties, parent)
end

function Collider2D:descriptor()
    local descriptor = self._descriptor or { _nodeOwner = self }
    self._descriptor = descriptor
    descriptor.shape, descriptor.size, descriptor.offset = self.shape, self.size, self.position
    descriptor.rotation, descriptor.radius, descriptor.vertices =
        self.rotation, self.radius, self.vertices
    descriptor.points = self.points
    for _, key in ipairs({
        'image',
        'imagePath',
        'collisionLevel',
        'imageResolution',
        'alphaThreshold',
        'maxFixtures',
        'imageRevision',
    }) do
        descriptor[key] = self[key]
    end
    descriptor.loop, descriptor.density = self.loop, self.density
    descriptor.friction, descriptor.restitution, descriptor.isTrigger =
        self.friction, self.restitution, self.isTrigger
    return descriptor
end

function Collider2D:setPoints(points)
    require('source.engine.physics.2d.geometry.polygon').parts(points)
    self.points, self.shape = points, 'Polygon'
    return self
end

return Collider2D
