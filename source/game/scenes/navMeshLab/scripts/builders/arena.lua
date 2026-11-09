local Mesh = require('source.engine.composition.mesh')

-- The walled arena: floor, four walls and three low curbs that agents can only jump over (a curb
-- is higher than the walkable step but lower than the jump height).
local Arena = {}

Arena.SIZE = 80
Arena.WALLS = {
    { 0, -10, 24, 2 },
    { -14, 8, 2, 20 },
    { 14, 8, 2, 20 },
    { 0, 16, 14, 2 },
}
Arena.CURB_HEIGHT = 0.9

-- A static box with a matching visual. `rotation` is in degrees.
function Arena.box(world, name, center, size, color, rotation)
    local body = world:create('Body3D', {
        name = name,
        bodyType = 'Static',
        position = center,
        size = size,
        rotation = rotation,
    })
    Mesh.create(world, { name = name .. 'Visual', size = size, color = color }, body)
    return body
end

function Arena.build(world)
    local floor = world:create('Body3D', {
        name = 'Floor',
        bodyType = 'Static',
        position = { 0, -0.5, 0 },
        size = { Arena.SIZE, 1, Arena.SIZE },
    })
    Mesh.create(world, {
        name = 'FloorVisual',
        size = { Arena.SIZE, 1, Arena.SIZE },
        surfaceAppearance = { colorMap = 'stone' },
    }, floor)
    for index, w in ipairs(Arena.WALLS) do
        Arena.box(world, 'Wall' .. index, { w[1], 1.5, w[2] }, { w[3], 3, w[4] }, { 0.55, 0.5, 0.45, 1 })
    end
    local half = Arena.CURB_HEIGHT / 2
    local color = { 0.75, 0.7, 0.55, 1 }
    -- Two curbs across the walkers' start line leave a gap in the middle (where the pillar slides).
    Arena.box(world, 'CurbWest', { -26, half, -17 }, { 28, Arena.CURB_HEIGHT, 1 }, color)
    Arena.box(world, 'CurbEast', { 26, half, -17 }, { 28, Arena.CURB_HEIGHT, 1 }, color)
end

return Arena
