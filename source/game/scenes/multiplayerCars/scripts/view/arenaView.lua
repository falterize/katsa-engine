-- Builds the visible arena: a ground mesh that follows Arena.ground, walls, pillars and lights.
local Geometry = require('source.engine.graphics.geometry.primitives')
local Arena = require('../game.arena')

local ArenaView = {}

local function groundGeometry()
    local half, step = Arena.size / 2, 2
    local vertices = {}
    local function point(x, z)
        local h = Arena.ground(x, z)
        local e = 0.05
        local nx = Arena.ground(x - e, z) - Arena.ground(x + e, z)
        local nz = Arena.ground(x, z - e) - Arena.ground(x, z + e)
        local length = math.sqrt(nx * nx + 4 * e * e + nz * nz)
        return { x, h, z, x / 6, z / 6, nx / length, 2 * e / length, nz / length }
    end
    for x = -half, half - step, step do
        for z = -half, half - step, step do
            local a, b = point(x, z), point(x + step, z)
            local c, d = point(x + step, z + step), point(x, z + step)
            vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = a, d, c
            vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = a, c, b
        end
    end
    local geometry = Geometry.mesh(vertices)
    return geometry
end

-- The same height field as a static triangle mesh (counter-clockwise from above) for physics.
local function groundCollider()
    local half, step = Arena.size / 2, 2
    local count = Arena.size / step + 1
    local vertices, indices = {}, {}
    for i = 0, count - 1 do
        for j = 0, count - 1 do
            local x, z = -half + i * step, -half + j * step
            vertices[#vertices + 1] = { x, Arena.ground(x, z), z }
        end
    end
    local function at(i, j)
        return i * count + j + 1
    end
    for i = 0, count - 2 do
        for j = 0, count - 2 do
            local a, b, c, d = at(i, j), at(i + 1, j), at(i + 1, j + 1), at(i, j + 1)
            for _, index in ipairs({ a, d, c, a, c, b }) do
                indices[#indices + 1] = index
            end
        end
    end
    return { shape = 'Mesh', vertices = vertices, indices = indices }
end

-- The car park: boxes for the deck, curbs, columns and a ramp. `solid` builds Body3D colliders,
-- otherwise the visible meshes. One list of boxes keeps both in step.
local function garageBoxes()
    local g = Arena.garage
    local r = g.ramp
    local boxes = {}
    local function box(name, cx, cy, cz, sx, sy, sz, rotation, color, floor)
        -- floor = the NavMap floor the box is ground of (the deck, curbs and ramp are floor 2)
        boxes[#boxes + 1] = { name, { cx, cy, cz }, { sx, sy, sz }, rotation, color, floor }
    end
    local width, depth = g.x1 - g.x0, g.z1 - g.z0
    local centerX, centerZ = (g.x0 + g.x1) / 2, (g.z0 + g.z1) / 2
    local grey, dark = { 0.5, 0.5, 0.52 }, { 0.38, 0.38, 0.4 }
    box('GarageDeck', centerX, g.deckY - g.thickness / 2, centerZ, width, g.thickness, depth, nil, grey, 2)
    local c = g.curb
    local top = g.deckY + c / 2
    box('GarageCurbS', centerX, top, g.z0 + 0.25, width, c, 0.5, nil, dark, 2)
    box('GarageCurbN', centerX, top, g.z1 - 0.25, width, c, 0.5, nil, dark, 2)
    box('GarageCurbW', g.x0 + 0.25, top, centerZ, 0.5, c, depth, nil, dark, 2)
    -- The east curb has an opening where the ramp arrives.
    local south = (r.z0 - g.z0)
    local north = (g.z1 - r.z1)
    box('GarageCurbES', g.x1 - 0.25, top, g.z0 + south / 2, 0.5, c, south, nil, dark, 2)
    box('GarageCurbEN', g.x1 - 0.25, top, g.z1 - north / 2, 0.5, c, north, nil, dark, 2)
    for index, column in ipairs(Arena.garageColumns()) do
        box('GarageColumn' .. index, column[1], (g.deckY - g.thickness) / 2, column[2], 1, g.deckY - g.thickness, 1, nil, dark)
    end
    -- The ramp: a slab tilted so its top surface runs from the ground (x1) up to the deck (x0).
    local length, rise = r.x1 - r.x0, g.deckY
    local angle = math.atan2(rise, length)
    local slab = math.sqrt(length * length + rise * rise)
    local t = 0.4
    box(
        'GarageRamp',
        (r.x0 + r.x1) / 2 - t / 2 * math.sin(angle),
        rise / 2 - t / 2 * math.cos(angle),
        (r.z0 + r.z1) / 2,
        slab,
        t,
        r.z1 - r.z0,
        { 0, 0, -math.deg(angle) },
        grey,
        2
    )
    return boxes
end

-- Static physics for the terrain and obstacles. Skipped when the scene has no Jolt world.
function ArenaView.buildPhysics(scene)
    local world = scene.world
    if not world.physics then
        return false
    end
    local ok, problem = pcall(function()
        world:create('Body3D', {
            name = 'GroundBody',
            bodyType = 'Static',
            size = { 1, 1, 1 },
            collider = groundCollider(),
        })
        for _, box in ipairs(garageBoxes()) do
            world:create('Body3D', {
                name = box[1] .. 'Body',
                bodyType = 'Static',
                position = box[2],
                size = box[3],
                rotation = box[4],
                navFloor = box[6],
            })
        end
        for index, obstacle in ipairs(Arena.obstacles) do
            local height = 3
            if obstacle.kind == 'box' then
                world:create('Body3D', {
                    name = 'WallBody' .. index,
                    bodyType = 'Static',
                    position = { obstacle.x, Arena.ground(obstacle.x, obstacle.z) + height / 2, obstacle.z },
                    size = { obstacle.halfX * 2, height, obstacle.halfZ * 2 },
                })
            else
                world:create('Body3D', {
                    name = 'PillarBody' .. index,
                    bodyType = 'Static',
                    position = { obstacle.x, Arena.ground(obstacle.x, obstacle.z) + 1, obstacle.z },
                    size = { obstacle.radius * 2, obstacle.radius * 2, obstacle.radius * 2 },
                    collider = { shape = 'Sphere', radius = obstacle.radius },
                })
            end
        end
    end)
    if not ok then
        katsa.log.warn('multiplayerCars: terrain physics unavailable: ' .. tostring(problem))
    end
    return ok
end

function ArenaView.build(scene)
    local world = scene.world
    -- The StareShooter look: panorama sky, soft sun with cascaded shadows and light haze.
    local environment = world.environment
    environment.debug.gizmos.enabled = false
    environment.ambient = { 130, 134, 144 }
    environment.toneMapping = false
    environment.sky.texture = 'scene://textures/sky.png'
    environment.sky.layout = 'Panorama'
    environment.fog.enabled = true
    environment.fog.color = { 199.6, 205.1, 213.7 }
    environment.fog.density = 0.006
    environment.fog.offset = 20
    environment.fog.maxOpacity = 0.85
    local shadows = environment.shadows
    shadows.enabled, shadows.resolution, shadows.distance = true, 2048, 60
    shadows.fadeDistance, shadows.near = 12, 0.05
    shadows.bias, shadows.normalBias = 0.001, 0.015
    require('source.engine.composition.mesh').create(world, {
        name = 'Ground',
        geometry = groundGeometry(),
        color = { 1, 1, 1 },
        surfaceAppearance = { colorMap = 'scene://textures/grass.png', roughness = 1 },
        position = { 0, 0, 0 },
    })
    for index, obstacle in ipairs(Arena.obstacles) do
        if obstacle.kind == 'box' then
            world:create('Mesh3D', {
                name = 'Wall' .. index,
                kind = 'cube',
                position = { obstacle.x, Arena.ground(obstacle.x, obstacle.z) + 1.5, obstacle.z },
                size = { obstacle.halfX * 2, 3, obstacle.halfZ * 2 },
                color = { 0.55, 0.5, 0.45 },
            })
        else
            world:create('Mesh3D', {
                name = 'Pillar' .. index,
                kind = 'sphere',
                position = { obstacle.x, Arena.ground(obstacle.x, obstacle.z) + 1, obstacle.z },
                size = { obstacle.radius * 2, obstacle.radius * 2, obstacle.radius * 2 },
                color = { 0.6, 0.35, 0.3 },
            })
        end
    end
    for _, box in ipairs(garageBoxes()) do
        world:create('Mesh3D', {
            name = box[1],
            kind = 'cube',
            position = box[2],
            size = box[3],
            rotation = box[4],
            color = box[5],
        })
    end
    ArenaView.buildPhysics(scene)
    world:create('DirectionalLight3D', {
        name = 'Sun',
        direction = { 0.5, -0.75, -0.43301266 },
        color = { 255, 255, 255 },
        brightness = 0.9,
        castShadow = true,
    })
end

return ArenaView
