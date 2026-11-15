-- Builds the visible arena: a ground mesh that follows Arena.ground, walls, pillars and lights.
local Geometry = require('source.engine.graphics.geometry.primitives')
local Arena = require('../shared.arena')
local Statics = require('../shared.arenaStatics')

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

-- Creates the Mesh3D of a piece. Under its Body3D the mesh sits at the body's origin; without
-- physics it takes the piece's own transform.
local function createVisual(world, piece, parent)
    local visual = piece.visual
    local properties = {
        name = piece.name .. 'Visual',
        kind = visual.kind,
        geometry = visual.geometry == 'terrain' and groundGeometry() or nil,
        color = visual.color,
        size = piece.size,
        surfaceAppearance = visual.surfaceAppearance,
    }
    if properties.geometry then
        properties.size = nil -- the terrain geometry is authored in world units
    end
    if parent.className == 'Node3D' then
        properties.name = piece.name
        properties.position, properties.rotation = piece.position, piece.rotation
    end
    return require('source.engine.composition.mesh').create(world, properties, parent)
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
    shadows.enabled, shadows.resolution, shadows.distance = true, 1024, 60
    shadows.fadeDistance, shadows.near = 12, 0.05
    shadows.bias, shadows.normalBias = 0.001, 0.015
    Statics.build(scene, createVisual)
    world:create('DirectionalLight3D', {
        name = 'Sun',
        direction = { 0.5, -0.75, -0.43301266 },
        color = { 255, 255, 255 },
        brightness = 0.9,
        castShadow = true,
    })
end

return ArenaView
