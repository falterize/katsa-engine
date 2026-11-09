local Mesh = require('source.engine.composition.mesh')
local Arena = require('./arena')

-- The jump yard east of the arena: a long curb, a pond (NavArea3D), a small platform reached by a
-- ramp or a staircase, and a ladder (NavLink3D 'climb') on its south face. Dimensions are chosen so
-- that, with a 1 unit cell, the steps (0.5) are walkable, the curb (0.9) is a jump and the
-- platform (2) is a drop.
local Yard = {}

Yard.PLATFORM = { 30, 24 } -- centre x, z; the top is at height 2
Yard.POINTS = {
    ground = { 18, 0, 14 },
    platform = { 30, 2, 24 },
    ladderFoot = { 30, 0, 31 },
    eastGround = { 38, 0, 22 },
    pondWest = { 18, 0, 36 },
    pondEast = { 38, 0, 36 },
}

function Yard.build(world)
    local color = { 0.6, 0.62, 0.7, 1 }
    Arena.box(world, 'YardCurb', { 27.5, Arena.CURB_HEIGHT / 2, 8 }, { 25, Arena.CURB_HEIGHT, 1 }, { 0.75, 0.7, 0.55, 1 })
    Arena.box(world, 'Platform', { 30, 1, 24 }, { 8, 2, 8 }, color)
    -- Four steps of 0.5 rising toward the platform's west face (x = 26).
    for step = 1, 4 do
        local x = 26 - 1.4 * (4 - step) - 0.7
        Arena.box(world, 'Step' .. step, { x, step * 0.25, 24 }, { 1.4, step * 0.5, 8 }, color)
    end
    -- A ramp from z = 12 (ground) to z = 20 (the platform's north face): rise 2 over run 8.
    local angle = math.deg(math.atan(2 / 8))
    local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
    Arena.box(
        world,
        'Ramp',
        { 30, 1 - 0.2 * c, 16 + 0.2 * s },
        { 6, 0.4, math.sqrt(68) },
        color,
        { angle, 0, 0 }
    )
    -- The pond (south of the platform) is only a picture for the eyes; the NavArea3D below is what
    -- agents price.
    Mesh.create(world, {
        name = 'PondVisual',
        size = { 6, 0.06, 6 },
        color = { 0.15, 0.4, 0.85, 0.7 },
        position = { 28, 0.04, 36 },
    })
    world:create('NavArea3D', { name = 'Pond', area = 'water', size = { 6, 3, 6 }, position = { 28, 0, 36 } })
end

-- Nodes that need the baked map: the ladder joining the ground south of the platform with its top.
function Yard.link(world, map)
    return world:create('NavLink3D', {
        name = 'Ladder',
        navMap = map,
        action = 'climb',
        position = Yard.POINTS.ladderFoot,
        endNode = world:create('Node3D', { name = 'LadderTop', position = { 30, 2, 25 } }),
        bidirectional = true,
    })
end

return Yard
