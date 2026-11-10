-- The arena's static pieces: terrain, walls, pillars and the car park, as Body3D colliders. Shared
-- by the client (which adds visible meshes through `visualize`) and the server (physics only).
local Arena = require('./arena')

local Statics = {}

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
        -- floor = the NavMap3D floor the box is ground of (the deck, curbs and ramp are floor 2)
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

-- Every static piece of the arena once: the terrain, the walls, the pillars and the car park.
-- A piece is a Body3D (when the world has physics) that owns its visible Mesh3D as a child, so the
-- Explorer shows `Wall1 > Wall1Visual` instead of two unrelated lists. `visual` describes the mesh
-- (`properties` for Mesh3D, `surfaceAppearance` for its material).
local function statics()
    local pieces = {
        {
            name = 'Ground',
            position = { 0, 0, 0 },
            size = { 1, 1, 1 },
            collider = groundCollider,
            visual = {
                geometry = 'terrain', -- the client builds the mesh (view/arenaView.lua)
                color = { 1, 1, 1 },
                surfaceAppearance = { colorMap = 'scene://textures/grass.png', roughness = 1 },
            },
        },
    }
    local height = 3
    for index, obstacle in ipairs(Arena.obstacles) do
        local base = Arena.ground(obstacle.x, obstacle.z)
        if obstacle.kind == 'box' then
            pieces[#pieces + 1] = {
                name = 'Wall' .. index,
                position = { obstacle.x, base + height / 2, obstacle.z },
                size = { obstacle.halfX * 2, height, obstacle.halfZ * 2 },
                visual = { kind = 'cube', color = { 0.55, 0.5, 0.45 } },
            }
        else
            local diameter = obstacle.radius * 2
            pieces[#pieces + 1] = {
                name = 'Pillar' .. index,
                position = { obstacle.x, base + 1, obstacle.z },
                size = { diameter, diameter, diameter },
                collider = function()
                    return { shape = 'Sphere', radius = obstacle.radius }
                end,
                visual = { kind = 'sphere', color = { 0.6, 0.35, 0.3 } },
            }
        end
    end
    for _, box in ipairs(garageBoxes()) do
        pieces[#pieces + 1] = {
            name = box[1],
            position = box[2],
            size = box[3],
            rotation = box[4],
            navFloor = box[6],
            visual = { kind = 'cube', color = box[5] },
        }
    end
    return pieces
end

function Statics.createBody(world, piece, parent)
    return world:create('Body3D', {
        name = piece.name,
        bodyType = 'Static',
        position = piece.position,
        size = piece.size,
        rotation = piece.rotation,
        navFloor = piece.navFloor,
        collider = piece.collider and piece.collider(),
    }, parent)
end

-- Builds every piece once under an `Arena` Node3D. `visualize(world, piece, parent)` (optional)
-- adds the piece's visible mesh; physics-only callers pass nil. Returns whether the bodies could
-- be created.
function Statics.build(scene, visualize)
    local world = scene.world
    local pieces = statics()
    local arena = world:create('Node3D', { name = 'Arena' })
    local bodies = false
    if world.physics then
        bodies = pcall(function()
            for _, piece in ipairs(pieces) do
                local body = Statics.createBody(world, piece, arena)
                if visualize then
                    visualize(world, piece, body)
                    piece.visualDone = true
                end
            end
        end)
        if not bodies then
            katsa.log.warn('multiplayerCars: terrain physics unavailable')
        end
    end
    if visualize and not bodies then
        for _, piece in ipairs(pieces) do
            if not piece.visualDone then
                visualize(world, piece, arena)
            end
        end
    end
    return bodies
end

return Statics
