local Node = require('../core.baseNode')

local Class = Node.define('Camera3D', 'Node3D')

function Class.mount(world, properties, parent)
    return world:addCamera(properties, parent)
end

return Class
