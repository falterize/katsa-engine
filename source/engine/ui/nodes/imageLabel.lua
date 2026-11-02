local Node = require('../../nodes')

local Class = Node.define('ImageLabel', 'Frame')
require('../../components.image').describe(Class)

function Class.initialize(self)
    require('../../components.image').initialize(self)
end

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    require('../drawing.image').draw(ui, self)
    if self.text then
        ui:drawText(self)
    end
end

return Class
