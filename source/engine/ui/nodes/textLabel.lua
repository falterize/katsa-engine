local Node = require('source.engine.nodes')

local Class = Node.define('TextLabel', 'Frame')

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    ui:drawText(self)
end

return Class
