-- Builds the visible arena: a ground mesh that follows Arena.ground, walls, pillars and lights.
local Geometry = require('source.engine.graphics.geometry.primitives')
local Arena = require('scene.scripts.game.arena')

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
        return { x, h, z, x / 8, z / 8, nx / length, 2 * e / length, nz / length }
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
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.ambient = { 120, 125, 140 }
    scene.camera.drawDistance = 400
    world:create('Mesh3D', {
        name = 'Ground',
        geometry = groundGeometry(),
        color = { 0.28, 0.42, 0.26 },
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
    ArenaView.buildPhysics(scene)
    world:addLight({
        name = 'Sun',
        position = { 0, 90, -30 },
        range = 400,
        radius = 40,
        brightness = 1.6,
        color = { 255, 240, 215 },
    })
    world:addLight({
        name = 'Fill',
        position = { 0, 40, 40 },
        range = 300,
        radius = 30,
        brightness = 0.6,
        color = { 150, 175, 255 },
    })
end

return ArenaView
