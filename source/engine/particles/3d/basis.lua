-- One orientation basis is used by visible sprites and their shadow geometry.
local M = require('source.engine.math.math3d')

local B = {}

function B.resolve(emitter, p, camera, matrix)
    local right, up = camera.right, camera.up
    if emitter.orientation == 'Velocity' then
        local vx, vy, vz = p.vx, p.vy, p.vz
        if p.space == 'Local' then
            vx, vy, vz = M.transform(matrix, vx, vy, vz, 0)
        end
        if vx * vx + vy * vy + vz * vz > 1e-10 then
            local ux, uy, uz = M.normalize(vx, vy, vz)
            local rx, ry, rz =
                uy * camera.forward[3] - uz * camera.forward[2],
                uz * camera.forward[1] - ux * camera.forward[3],
                ux * camera.forward[2] - uy * camera.forward[1]
            if rx * rx + ry * ry + rz * rz > 1e-10 then
                rx, ry, rz = M.normalize(rx, ry, rz)
                return rx, ry, rz, ux, uy, uz
            end
        end
    elseif emitter.orientation == 'Axes' then
        local rx, ry, rz = M.normalize(
            M.transform(matrix, emitter.axisRight[1], emitter.axisRight[2], emitter.axisRight[3], 0)
        )
        local ux, uy, uz =
            M.transform(matrix, emitter.axisUp[1], emitter.axisUp[2], emitter.axisUp[3], 0)
        local dot = ux * rx + uy * ry + uz * rz
        ux, uy, uz = M.normalize(ux - dot * rx, uy - dot * ry, uz - dot * rz)
        return rx, ry, rz, ux, uy, uz
    end
    return right[1], right[2], right[3], up[1], up[2], up[3]
end

return B
