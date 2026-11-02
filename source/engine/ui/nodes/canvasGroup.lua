local Node = require('../../nodes')

local CanvasGroup = Node.define('CanvasGroup', 'Frame')

function CanvasGroup.initialize(self)
    self.zIndex = self.zIndex or 0
    self.transparency = self.transparency or 0
    self.capture = self.capture == true
end

return CanvasGroup
