local unpack = require('../../math.array').unpack
local Node = require('../../nodes')

local Class = Node.define('Button', 'Label')
Class.interactive = true
require('../../components.media.image').describe(Class)

function Class.initialize(self)
    require('source.engine.components.media.image').initialize(self)
    if
        not self._backgroundAuthored
        and (not self.image or self.image == '')
        and self.imageMode ~= 'XML'
    then
        self.backgroundColor = { unpack(require('source.engine.ui.theme').button) }
        if not self._backgroundTransparencyAuthored then
            self.backgroundTransparency = 0
        end
    end
end

function Class:drawSelf(ui)
    if self.image ~= nil or self.imageMode == 'XML' or self._xmlBinding then
        Node.getClass('Frame').drawSelf(self, ui)
        require('source.engine.ui.drawing.image').draw(ui, self)
        ui:drawText(self)
    else
        Class.base.drawSelf(self, ui)
    end
end

return Class
