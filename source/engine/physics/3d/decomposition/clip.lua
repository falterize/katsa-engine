-- Clips triangles to an axis-aligned box (Sutherland-Hodgman, one plane at a time).
local Clip = {}

-- Keeps the part of `polygon` where keep * (p[axis] - value) >= 0. Returns a new polygon.
local function clipPlane(polygon, axis, value, keep)
    local result, count = {}, #polygon
    for i = 1, count do
        local a, b = polygon[i], polygon[i % count + 1]
        local da, db = (a[axis] - value) * keep, (b[axis] - value) * keep
        if da >= 0 then
            result[#result + 1] = a
        end
        if (da >= 0) ~= (db >= 0) then
            local t = da / (da - db)
            result[#result + 1] = {
                a[1] + (b[1] - a[1]) * t,
                a[2] + (b[2] - a[2]) * t,
                a[3] + (b[3] - a[3]) * t,
            }
        end
    end
    return result
end

-- polygon: list of { x, y, z }. lo / hi: { x, y, z } bounds where `false` leaves a side open.
-- Returns the clipped polygon, or nil when nothing is left.
function Clip.polygon(polygon, lo, hi)
    for axis = 1, 3 do
        if lo[axis] then
            polygon = clipPlane(polygon, axis, lo[axis], 1)
            if #polygon < 3 then
                return nil
            end
        end
        if hi[axis] then
            polygon = clipPlane(polygon, axis, hi[axis], -1)
            if #polygon < 3 then
                return nil
            end
        end
    end
    return polygon
end

return Clip
