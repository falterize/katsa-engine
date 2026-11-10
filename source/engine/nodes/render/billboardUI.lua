local Node = require('../core.baseNode')

local Class = Node.define('BillboardUI', 'Node3D')
Class.propertySchema = {
    pixelate = {
        get = function(node)
            return require('source.engine.components.media.image').pixelate(node, node._world.environment)
        end,
    },
}

function Class.mount(world, properties, parent)
    properties.parent = parent or properties.parent
    local node = require('source.engine.ui.spatial.billboard').new(world, properties)
    if parent then
        node.parent = parent
    end
    return node
end

return Class
