-- Bounding sphere of a list of spatial items ({ position = {x,y,z}, size = {x,y,z} }). Pure Lua.
local Bounds = {}

-- Returns center { x, y, z } and radius, or nil for an empty list. The size is the full extent
-- of the item (a unit cube has size 1), so its half-diagonal is added to the distance.
function Bounds.sphere(items)
    local count = #items
    if count == 0 then
        return nil
    end
    local cx, cy, cz = 0, 0, 0
    for _, item in ipairs(items) do
        cx, cy, cz = cx + item.position[1], cy + item.position[2], cz + item.position[3]
    end
    cx, cy, cz = cx / count, cy / count, cz / count
    local radius = 0
    for _, item in ipairs(items) do
        local size = item.size or { 1, 1, 1 }
        local half = 0.5 * math.sqrt(size[1] ^ 2 + size[2] ^ 2 + size[3] ^ 2)
        local dx, dy, dz = item.position[1] - cx, item.position[2] - cy, item.position[3] - cz
        radius = math.max(radius, math.sqrt(dx * dx + dy * dy + dz * dz) + half)
    end
    return { cx, cy, cz }, radius
end

return Bounds
