local unpack = require('../../math.array').unpack
local Math = require('../../math.math3d')
local ShadowProjection = {}

function ShadowProjection.install(
    position,
    direction,
    extent,
    near,
    far,
    orthographic,
    out,
    view,
    projection
)
    local fx, fy, fz = Math.normalize(unpack(direction))
    local rx, ry, rz
    if math.abs(fy) > 0.99 then
        rx, ry, rz = Math.normalize(fz, 0, -fx + 0.00001)
    else
        rx, ry, rz = Math.normalize(fz, 0, -fx)
    end
    local ux, uy, uz = fy * rz - fz * ry, fz * rx - fx * rz, fx * ry - fy * rx
    view[1], view[2], view[3], view[4] =
        rx, ry, rz, -(rx * position[1] + ry * position[2] + rz * position[3])
    view[5], view[6], view[7], view[8] =
        ux, uy, uz, -(ux * position[1] + uy * position[2] + uz * position[3])
    view[9], view[10], view[11], view[12] =
        fx, fy, fz, -(fx * position[1] + fy * position[2] + fz * position[3])
    for i = 1, 16 do
        projection[i] = 0
    end
    if orthographic then
        projection[1], projection[6], projection[11] = 1 / extent, -1 / extent, 2 / (far - near)
        projection[12], projection[16] = -(far + near) / (far - near), 1
    else
        projection[1], projection[6] = 1 / extent, -1 / extent
        projection[11], projection[12], projection[15] =
            (far + near) / (far - near), -2 * far * near / (far - near), 1
    end
    Math.multiply(projection, view, out)
end

return ShadowProjection
