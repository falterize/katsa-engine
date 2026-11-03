local Node = require('../core.baseNode')

local Class = Node.define('PointLight3D', 'Node3D')

require('../../components.shadowing').describe(Class, { receive = false, cutoff = false })

function Class.initialize(self)
    require('source.engine.components.shadowing').normalize(self, { castShadow = true })
end

function Class.mount(world, properties, parent)
    properties.parent = parent
    properties.type = properties.className
    return world:addLight(properties)
end

return Class
