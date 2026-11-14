local Mesh = require('source.engine.composition.mesh')
local Arena = require('../../scripts.shared.arena')

-- The client's own world: light, sky, the ground and the two areas. These are local scenery; every
-- game object (Round, Players, Coins, Platform) comes from the server.
local Level = {}

local function area(world, name, center, radius, color)
    Mesh.create(world, {
        name = name,
        position = { center[1], 0.02, center[3] },
        size = { radius * 2, 0.04, radius * 2 },
        color = color,
        castShadow = false,
    })
end

function Level.create(scene)
    local world, environment = scene.world, scene.world.environment
    environment.debug.gizmos.enabled = false
    environment.ambient = { 150, 156, 168 }
    environment.fog.enabled = false
    environment.sky.enabled = true
    environment.shadows.enabled = true
    environment.shadows.distance = 40
    Mesh.create(world, {
        name = 'Ground',
        position = { 0, -0.25, 0 },
        size = { 300, 0.5, 300 },
        surfaceAppearance = { colorMap = 'stone', roughness = 1 },
    })
    area(world, 'Lobby', Arena.lobby, Arena.lobbyRadius, { 0.35, 0.55, 0.8, 1 })
    area(world, 'Arena', Arena.arena, Arena.arenaRadius, { 0.8, 0.47, 0.35, 1 })
    -- A boundary for the local character; the server checks the pose it reports.
    world:create('Body3D', {
        name = 'WorldBoundary',
        bodyType = 'Static',
        position = { 0, -1, 0 },
        size = { 2000, 2, 2000 },
        friction = 0,
        restitution = 0,
    })
    world:create('DirectionalLight3D', {
        name = 'Sun',
        direction = { 0.5, -0.75, -0.43301266 },
        color = { 255, 255, 255 },
        brightness = 0.9,
        castShadow = true,
    })
end

return Level
