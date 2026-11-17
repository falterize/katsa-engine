-- Voxel ray traversal (Amanatides and Woo): the first solid block along a ray and the empty
-- block in front of it, which is where a new block goes.
local Raycast = {}

local huge = math.huge

function Raycast.cast(world, ox, oy, oz, dx, dy, dz, reach)
    local x, y, z = math.floor(ox), math.floor(oy), math.floor(oz)
    local stepX, stepY, stepZ = dx > 0 and 1 or -1, dy > 0 and 1 or -1, dz > 0 and 1 or -1
    local tx = dx ~= 0 and ((dx > 0 and x + 1 - ox or ox - x) / math.abs(dx)) or huge
    local ty = dy ~= 0 and ((dy > 0 and y + 1 - oy or oy - y) / math.abs(dy)) or huge
    local tz = dz ~= 0 and ((dz > 0 and z + 1 - oz or oz - z) / math.abs(dz)) or huge
    local deltaX = dx ~= 0 and 1 / math.abs(dx) or huge
    local deltaY = dy ~= 0 and 1 / math.abs(dy) or huge
    local deltaZ = dz ~= 0 and 1 / math.abs(dz) or huge
    local px, py, pz
    local distance = 0
    while distance <= reach do
        local id = world:getBlock(x, y, z)
        if id == nil then
            return nil
        elseif id ~= 0 then
            return { x = x, y = y, z = z, id = id, px = px, py = py, pz = pz }
        end
        px, py, pz = x, y, z
        if tx < ty and tx < tz then
            x, distance, tx = x + stepX, tx, tx + deltaX
        elseif ty < tz then
            y, distance, ty = y + stepY, ty, ty + deltaY
        else
            z, distance, tz = z + stepZ, tz, tz + deltaZ
        end
    end
    return nil
end

return Raycast
