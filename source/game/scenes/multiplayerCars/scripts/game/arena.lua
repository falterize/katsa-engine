-- The shared playfield: ground height, static obstacles and the pathfinding grid.
-- Pure Lua so the server, the clients (prediction) and the bot all see the same world.
local Arena = {
    size = 120, -- square, centered on the origin
    cellSize = 2,
}

local half = Arena.size / 2

-- Gentle rolling ground so the springs have something to do.
function Arena.ground(x, z)
    local base = 0.35 * math.sin(x * 0.12) * math.cos(z * 0.1)
    -- A small ramp strip along x = 20..26
    if x > 20 and x < 26 and z > -30 and z < -10 then
        base = base + (x - 20) / 6 * 0.9
    end
    return base
end

-- Circle: { kind = 'circle', x, z, radius }. Box: { kind = 'box', x, z, halfX, halfZ }.
Arena.obstacles = {
    { kind = 'box', x = 0, z = half + 1, halfX = half + 2, halfZ = 1 },
    { kind = 'box', x = 0, z = -half - 1, halfX = half + 2, halfZ = 1 },
    { kind = 'box', x = half + 1, z = 0, halfX = 1, halfZ = half + 2 },
    { kind = 'box', x = -half - 1, z = 0, halfX = 1, halfZ = half + 2 },
    { kind = 'box', x = -20, z = 15, halfX = 8, halfZ = 2 },
    { kind = 'box', x = 12, z = 20, halfX = 2, halfZ = 10 },
    { kind = 'box', x = -5, z = -20, halfX = 10, halfZ = 2 },
    { kind = 'circle', x = 30, z = 30, radius = 4 },
    { kind = 'circle', x = -35, z = -30, radius = 5 },
    { kind = 'circle', x = 0, z = 0, radius = 3 },
}

-- Spawn points around the arena for players; the first is also used for the bot's home.
Arena.spawns = {
    { -40, 40, 135 },
    { 40, -40, 315 },
    { -40, -45, 45 },
    { 45, 45, 225 },
    { 0, -45, 0 },
    { 0, 45, 180 },
}

-- Cells are 1-based; the grid origin is the arena corner. `margin` inflates obstacles by the
-- car's size so planned routes never graze a wall.
function Arena.buildGrid(Grid, margin)
    margin = margin or 1.6
    local cells = math.floor(Arena.size / Arena.cellSize)
    local grid = Grid.new(cells, cells, { cellSize = Arena.cellSize, origin = { -half, -half } })
    grid:bake(function(x, z)
        for _, obstacle in ipairs(Arena.obstacles) do
            if obstacle.kind == 'circle' then
                local dx, dz = x - obstacle.x, z - obstacle.z
                local reach = obstacle.radius + margin
                if dx * dx + dz * dz < reach * reach then
                    return true
                end
            elseif
                math.abs(x - obstacle.x) < obstacle.halfX + margin
                and math.abs(z - obstacle.z) < obstacle.halfZ + margin
            then
                return true
            end
        end
        return false
    end)
    return grid
end

return Arena
