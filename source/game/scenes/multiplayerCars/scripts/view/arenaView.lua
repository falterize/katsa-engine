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
                position = { obstacle.x, 1.5, obstacle.z },
                size = { obstacle.halfX * 2, 3, obstacle.halfZ * 2 },
                color = { 0.55, 0.5, 0.45 },
            })
        else
            world:create('Mesh3D', {
                name = 'Pillar' .. index,
                kind = 'sphere',
                position = { obstacle.x, 1, obstacle.z },
                size = { obstacle.radius * 2, obstacle.radius * 2, obstacle.radius * 2 },
                color = { 0.6, 0.35, 0.3 },
            })
        end
    end
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
