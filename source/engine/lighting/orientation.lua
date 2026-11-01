local unpack = require('source.engine.math.array').unpack
-- Convert imported ray directions to the engine's Rotation convention.
local M = require('source.engine.math.math3d')

local Orientation = {}

function Orientation.rotation(direction)
    assert(
        direction[1] ^ 2 + direction[2] ^ 2 + direction[3] ^ 2 > 1e-12,
        'Light direction must be nonzero'
    )
    local x, y, z = M.normalize(unpack(direction))
    return { math.deg(math.asin(math.max(-1, math.min(1, -y)))), math.deg(math.atan2(-x, z)), 0 }
end

return Orientation
