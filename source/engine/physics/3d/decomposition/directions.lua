-- Direction sets and "extreme point" reduction.
--
-- The extreme point of a cloud along a direction is the point with the largest dot product. The
-- hull of the extremes along enough well-spread directions is a close, cheap stand-in for the hull
-- of the whole cloud: it has at most one vertex per direction and keeps the silhouette.
local Directions = {}

local sqrt, cos, sin = math.sqrt, math.cos, math.sin

local cache = {}

-- `count` roughly uniform unit vectors (Fibonacci spiral), preceded by the six axis directions
-- so a box-like model always keeps its corners' extents.
function Directions.rich(count)
    count = math.max(6, math.floor(count))
    local list = cache[count]
    if list then
        return list
    end
    list = {
        { 1, 0, 0 },
        { -1, 0, 0 },
        { 0, 1, 0 },
        { 0, -1, 0 },
        { 0, 0, 1 },
        { 0, 0, -1 },
    }
    local extra = count - 6
    local golden = math.pi * (3 - sqrt(5))
    for i = 0, extra - 1 do
        local y = 1 - 2 * (i + 0.5) / extra
        local radius = sqrt(math.max(0, 1 - y * y))
        local angle = i * golden
        list[#list + 1] = { cos(angle) * radius, y, sin(angle) * radius }
    end
    cache[count] = list
    return list
end

-- The 26 directions of a 3x3x3 lattice (faces, edges, corners of a cube), normalised. Used by the
-- voxel analysis, where cell-aligned extremes are exact along these.
local lattice
function Directions.lattice()
    if lattice then
        return lattice
    end
    lattice = {}
    for x = -1, 1 do
        for y = -1, 1 do
            for z = -1, 1 do
                if x ~= 0 or y ~= 0 or z ~= 0 then
                    local length = sqrt(x * x + y * y + z * z)
                    lattice[#lattice + 1] = { x / length, y / length, z / length }
                end
            end
        end
    end
    return lattice
end

-- Returns the distinct points (the same tables as the input) that are extreme along `directions`.
function Directions.extremes(points, directions)
    local count = #directions
    local best, index = {}, {}
    for d = 1, count do
        best[d] = -math.huge
    end
    for i = 1, #points do
        local p = points[i]
        local x, y, z = p[1], p[2], p[3]
        for d = 1, count do
            local dir = directions[d]
            local value = dir[1] * x + dir[2] * y + dir[3] * z
            if value > best[d] then
                best[d], index[d] = value, i
            end
        end
    end
    local result, taken = {}, {}
    for d = 1, count do
        local i = index[d]
        if i and not taken[i] then
            taken[i] = true
            result[#result + 1] = points[i]
        end
    end
    return result
end

return Directions
