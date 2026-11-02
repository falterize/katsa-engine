-- The shared playfield: ground height, static obstacles and the pathfinding grid.
-- Pure Lua so the server, the clients (prediction) and the bot all see the same world.
local Arena = {
    size = 120, -- square, centered on the origin
    cellSize = 2,
}

local half = Arena.size / 2

-- Terrain features: smooth cosine hills { x, z, radius, height } and rectangular ramps.
-- A test track for the suspension and for slope-aware pathfinding.
local hills = {
    { -30, -10, 15, 4 }, -- broad hill, drivable
    { 42, -12, 6, 5 }, -- steep rock: too steep for the bot's route planner
    { 38, 38, 10, 2.5 },
    { -10, 38, 9, -1.5 }, -- shallow bowl
}

local function smooth(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

-- Ground height at (x, z): rolling noise, hills, a ramp with a plateau and speed bumps.
function Arena.ground(x, z)
    local base = 0.35 * math.sin(x * 0.12) * math.cos(z * 0.1)
    for _, hill in ipairs(hills) do
        local dx, dz = x - hill[1], z - hill[2]
        local d = math.sqrt(dx * dx + dz * dz)
        if d < hill[3] then
            base = base + hill[4] * 0.5 * (1 + math.cos(math.pi * d / hill[3]))
        end
    end
    -- Ramp up along +x (x = 20..30), a plateau to x = 34 and a drop back to ground by x = 40.
    local lane = smooth((z + 34) / 3) * smooth((-20 - z) / 3)
    if lane > 0 then
        local height = 0
        if x > 20 and x <= 30 then
            height = (x - 20) / 10 * 3
        elseif x > 30 and x <= 34 then
            height = 3
        elseif x > 34 and x < 40 then
            height = 3 * (1 - (x - 34) / 6)
        end
        base = base + height * lane
    end
    -- Three speed bumps across the south lane.
    for _, bump in ipairs({ 6, 12, 18 }) do
        if math.abs(z - (-bump * 2 - 24)) < 1.2 and x > -25 and x < 5 then
            base = base + 0.45 * math.cos((z + bump * 2 + 24) / 1.2 * math.pi * 0.5)
        end
    end
    return base
end

-- Steepness (rise over run) at (x, z).
function Arena.slope(x, z)
    local e = 0.5
    local dx = (Arena.ground(x + e, z) - Arena.ground(x - e, z)) / (2 * e)
    local dz = (Arena.ground(x, z + e) - Arena.ground(x, z - e)) / (2 * e)
    return math.sqrt(dx * dx + dz * dz)
end

Arena.maxDriveSlope = 0.6

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
        if Arena.slope(x, z) > Arena.maxDriveSlope then
            return true
        end
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
