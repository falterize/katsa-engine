local unpack = require('../../math.array').unpack
local Math = require('../../math.math3d')

local Cascades = {}
-- Each directional source uses three nested, camera-centred snapped maps.
Cascades.count = 3
Cascades.matrixRows = 32 * 6
Cascades.fractions = { 1 / 8, 1 / 3, 1 }

function Cascades.prepare(camera, direction, distance, resolution, cascade, position)
    local fx, fy, fz = Math.normalize(unpack(direction))
    local rx, ry, rz = Math.normalize(fz, 0, -fx + (math.abs(fy) > 0.99 and 0.00001 or 0))
    local ux, uy, uz = fy * rz - fz * ry, fz * rx - fx * rz, fx * ry - fy * rx
    local p = camera.worldPosition or camera.position
    local extent = distance * Cascades.fractions[cascade]
    local texel = 2 * extent / resolution
    local right = p[1] * rx + p[2] * ry + p[3] * rz
    local up = p[1] * ux + p[2] * uy + p[3] * uz
    local dr = math.floor(right / texel + 0.5) * texel - right
    local du = math.floor(up / texel + 0.5) * texel - up
    position[1], position[2], position[3] =
        p[1] + rx * dr + ux * du - fx * distance,
        p[2] + ry * dr + uy * du - fy * distance,
        p[3] + rz * dr + uz * du - fz * distance
    return extent, texel
end

return Cascades
