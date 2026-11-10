local Node = require('../../nodes')

local Class = Node.define('ImageRect', 'Frame')
require('../../components.media.image').describe(Class)

function Class.initialize(self)
    require('source.engine.components.media.image').initialize(self)
end

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    require('source.engine.ui.drawing.image').draw(ui, self)
    if self.text then
        ui:drawText(self)
    end
end

return Class
