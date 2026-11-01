local Node = require('source.engine.nodes')

local Class = Node.define('ImageLabel', 'Frame')
require('source.engine.components.image').describe(Class)

function Class.initialize(self)
    require('source.engine.components.image').initialize(self)
end

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    require('source.engine.ui.drawing.image').draw(ui, self)
    if self.text then
        ui:drawText(self)
    end
end

return Class
