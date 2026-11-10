local Node = require('../core.baseNode')
local Light = require('../../components.illumination.light')

-- The cone points along the node's rotation; range and radius shape it.
local Class = Node.define('SpotLight3D', 'Node3D')
Light.install(Class)

return Class
