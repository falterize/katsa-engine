local readValue = require('source.engine.math.managedValue').read
local Node = require('source.engine.nodes')

local Class = Node.define('UICorner', 'UINode')
Class.modifier = true

function Class.initialize(self)
    self.radius = self.radius or { self.radiusScale or 0, self.cornerRadius or 12 }
    self.radiusScale, self.cornerRadius = nil, nil
end

function Class:applyLayout(parent)
    local side = math.min(parent._width, parent._height)
    local radius = readValue(self.radius)
    parent._rounded = true
    parent._radius = math.max(0, math.min(side * 0.5, radius[1] * side + radius[2]))
end

function Class:drawSelf(ui) end
return Class
