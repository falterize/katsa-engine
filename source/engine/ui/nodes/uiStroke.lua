local Node = require('../../nodes')

local Stroke = Node.define('UIStroke', 'UINode')
Stroke.modifier = true

function Stroke.initialize(self)
    self.target = self.target or 'Border'
    self.color = self.color or { 0, 0, 0 }
    self.thickness = type(self.thickness) == 'number' and { 0, self.thickness }
        or self.thickness
        or { 0, 2 }
    self.transparency = self.transparency or 0
end

function Stroke:applyLayout(parent)
    assert(
        self.target == 'Border' or self.target == 'Text',
        'UIStroke.target must be Border or Text'
    )
end

function Stroke:drawSelf(ui) end
return Stroke
