-- Beam3D: a textured ribbon between two attachments (Roblox Beam). The centre line is a cubic
-- Bezier whose end tangents follow each attachment's X axis scaled by curveSize0 / curveSize1.
local Node = require('../core.baseNode')
local V = require('../../core.validate')
local Ribbon = require('./ribbon')

local C = Node.define('Beam3D', 'Node3D')
C.defaults = {
    width0 = 1,
    width1 = 1,
    curveSize0 = 0,
    curveSize1 = 0,
    segments = 10,
}
for key, value in pairs(Ribbon.defaults) do
    C.defaults[key] = value
end
C.defaults.textureLength = 4

Ribbon.describe(C, {
    attachment0 = {
        kind = 'node',
        nodeClass = 'Node3D',
        hint = 'Start of the beam: any Node3D (an Attachment3D is not required). The curve leaves '
            .. 'along its X axis.',
    },
    attachment1 = { kind = 'node', nodeClass = 'Node3D', hint = 'End of the beam: any Node3D.' },
    width0 = { min = 0, hint = 'Beam width at attachment0, in world units.' },
    width1 = { min = 0, hint = 'Beam width at attachment1, in world units.' },
    curveSize0 = { hint = 'Distance of the first Bezier control point along attachment0 X axis.' },
    curveSize1 = { hint = 'Distance of the second Bezier control point along attachment1 X axis.' },
    segments = {
        min = 1,
        max = 128,
        hint = 'Straight pieces the curve is cut into. A straight beam needs only 1.',
    },
})

function C.initialize(self)
    Ribbon.initialize(self, 'Beam3D', C.defaults)
    V.number(self.width0, 'Beam3D.width0', 0)
    V.number(self.width1, 'Beam3D.width1', 0)
    V.number(self.segments, 'Beam3D.segments', 1, 128)
end

function C.mount(world, properties, parent)
    return Ribbon.mount(world, properties, parent, 'Beam3D')
end

return C
