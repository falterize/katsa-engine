local Node = require('../../nodes')

local Class = Node.define('Label', 'Frame')
Class.propertySchema = {
    textKey = {
        hint = 'Localization key. When set, the text follows the current language '
            .. '(Localization.get():setLocale) and `text` is filled from the key.',
    },
}

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    ui:drawText(self)
end

return Class
