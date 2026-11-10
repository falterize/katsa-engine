local Node = require('../core.baseNode')
local Light = require('../../components.illumination.light')

-- A point has no direction, so the class has no rotation (and a light has no scale either).
local Class = Node.define('PointLight3D', 'Node3D')
Light.install(Class)

return Class
