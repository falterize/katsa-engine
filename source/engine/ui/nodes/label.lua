local Node = require('../../nodes')

local Class = Node.define('Label', 'Frame')

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    ui:drawText(self)
end

return Class
