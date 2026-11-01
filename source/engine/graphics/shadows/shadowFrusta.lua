local ipairs = require('source.engine.math.array').ipairs
-- Keep directional invalidation aligned with depth volumes, not main-camera visibility.
local Frusta = {}

function Frusta.prepare(matrices, out)
    out = out or {}
    for cascade = 1, 3 do
        local planes = out[cascade] or {}
        out[cascade] = planes
        local matrix = matrices[cascade]
        for axis = 1, 3 do
            for side = 0, 1 do
                local index, row, sign =
                    (axis - 1) * 2 + side + 1, (axis - 1) * 4, side == 0 and 1 or -1
                local plane = planes[index] or {}
                planes[index] = plane
                for i = 1, 4 do
                    plane[i] = matrix[12 + i] + sign * matrix[row + i]
                end
                plane[5] = math.sqrt(plane[1] ^ 2 + plane[2] ^ 2 + plane[3] ^ 2)
            end
        end
    end
    return out
end

function Frusta.intersects(bounds, frusta)
    if not frusta or bounds.unbounded then
        return true
    end
    for _, planes in ipairs(frusta) do
        local inside = true
        for _, p in ipairs(planes) do
            if
                p[1] * bounds.x + p[2] * bounds.y + p[3] * bounds.z + p[4]
                < -bounds.radius * p[5]
            then
                inside = false
                break
            end
        end
        if inside then
            return true
        end
    end
    return false
end

return Frusta
