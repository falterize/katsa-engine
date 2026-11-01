local Node = require('source.engine.nodes.core.baseNode')

local Class = Node.define('PointLight3D', 'Node3D')

function Class.initialize(self)
    self.castShadow = self.castShadow ~= false
end

function Class.mount(world, properties, parent)
    properties.parent = parent
    properties.type = properties.className
    return world:addLight(properties)
end

return Class
