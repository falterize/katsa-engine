local Node = require('../core.baseNode')

local Class = Node.define('Attachment3D', 'Node3D')

function Class.initialize(self)
    self.inheritScale = self.inheritScale == true
end

return Class
