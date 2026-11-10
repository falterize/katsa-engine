-- Trail3D: a ribbon that follows a moving node. Two modes:
--   Single  one node (attachment0, or the Trail3D itself) is the centre; the trail always turns its
--           width toward the camera and `width` sets the width.
--   Dual    two nodes mark the top and bottom edge like a Roblox Trail; their distance is the width.
-- The "attachments" can be any Node3D, so no Attachment3D is needed inside a model. Points are kept
-- for `lifetime` seconds, at least `minLength` apart.
local Node = require('../core.baseNode')
local V = require('../../core.validate')
local Ribbon = require('./ribbon')

local C = Node.define('Trail3D', 'Node3D')
C.defaults = {
    trailMode = 'Single',
    lifetime = 1.5,
    minLength = 0.1,
    maxLength = 0,
    maxPoints = 256,
    breakDistance = 10,
    width = 0.5,
}
for key, value in pairs(Ribbon.defaults) do
    C.defaults[key] = value
end

Ribbon.describe(C, {
    trailMode = {
        options = { 'Single', 'Dual' },
    },
    attachment0 = {
        kind = 'node',
        nodeClass = 'Node3D',
    },
    attachment1 = {
        kind = 'node',
        nodeClass = 'Node3D',
        visibleWhen = { key = 'trailMode', equals = 'Dual' },
    },
    lifetime = { min = 0.01 },
    minLength = {
        min = 0,
    },
    maxLength = { min = 0 },
    maxPoints = { min = 2, max = 1024 },
    breakDistance = {
        min = 0,
    },
    width = {
        min = 0,
        visibleWhen = { key = 'trailMode', equals = 'Single' },
    },
})
C.propertySchema.faceCamera.visibleWhen = { key = 'trailMode', equals = 'Dual' }

function C.initialize(self)
    Ribbon.initialize(self, 'Trail3D', C.defaults)
    assert(self.trailMode == 'Single' or self.trailMode == 'Dual', 'Trail3D.trailMode must be Single or Dual')
    V.number(self.lifetime, 'Trail3D.lifetime', 0.01)
    V.number(self.minLength, 'Trail3D.minLength', 0)
    V.number(self.maxLength, 'Trail3D.maxLength', 0)
    V.number(self.maxPoints, 'Trail3D.maxPoints', 2, 1024)
    V.number(self.breakDistance, 'Trail3D.breakDistance', 0)
    V.number(self.width, 'Trail3D.width', 0)
end

function C.mount(world, properties, parent)
    return Ribbon.mount(world, properties, parent, 'Trail3D')
end

-- Removes every stored point; the trail grows again from the current pose.
function C:clear()
    require('source.engine.ribbons.source').clear(self)
end

return C
