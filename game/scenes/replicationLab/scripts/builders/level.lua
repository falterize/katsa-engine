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
    environment.ambient = { 138, 150, 172 }
    environment.sky.enabled = true
    world:create('Shader3D', { name = 'SoftSky', shaderPath = 'scene://shaders/softSky.glsl' })
    -- A light, warm look: soft shadows, a little bloom and ambient occlusion, gentle haze.
    environment.shadows.enabled = true
    environment.shadows.distance = 60
    environment.glow.enabled = true
    environment.ssao.enabled = true
    environment.adjustments.enabled = true
    environment.adjustments.saturation = 1.12
    environment.adjustments.contrast = 1.05
    environment.render.screenSpaceAA = 'FXAA'
    environment.fog.enabled, environment.fog.volumetric = true, true
    environment.fog.density, environment.fog.volumetricDistance = 0.004, 120
    Mesh.create(world, {
        name = 'Ground',
        position = { 0, -0.25, 0 },
        size = { 300, 0.5, 300 },
        color = { 0.55, 0.72, 0.5, 1 },
        surfaceAppearance = { colorMap = 'stone', roughness = 1 },
    })
    area(world, 'Lobby', Arena.lobby, Arena.lobbyRadius, { 0.5, 0.68, 0.9, 1 })
    -- A boundary for the local character; the server checks the pose it reports.
    local boundary = world:create('Body3D', {
        name = 'WorldBoundary',
        bodyType = 'Static',
        position = { 0, -1, 0 },
        size = { 2000, 2, 2000 },
        friction = 0,
        restitution = 0,
    })
    boundary:addCollider({ name = 'Floor', shape = 'Box', size = { 2000, 2, 2000 } })
    world:create('DirectionalLight3D', {
        name = 'Sun',
        direction = { 0.5, -0.75, -0.43301266 },
        color = { 255, 238, 214 },
        brightness = 1.05,
        castShadow = true,
    })
end

return Level
