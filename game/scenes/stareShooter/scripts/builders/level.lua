local Mesh = require('source.engine.composition.mesh')
local Geometry = require('source.engine.graphics.geometry.primitives')

local Level = {}

-- A plane whose texture repeats `repeats` times over its size; the mesh belongs to the scene.
function Level.tiledPlane(scene, repeats)
    local geometry = Geometry.plane()
    for _, vertex in ipairs(geometry.vertices) do
        vertex[4], vertex[5] = vertex[4] * repeats, vertex[5] * repeats
    end
    geometry.mesh:setVertices(geometry.vertices)
    scene.resources:own(geometry.mesh)
    return geometry
end

function Level.create(scene)
    local world, environment = scene.world, scene.world.environment
    environment.debug.gizmos.enabled = false
    environment.ambient = { 130, 134, 144 }
    environment.toneMapping = false
    environment.sky.texture = 'scene://textures/sky.png'
    environment.sky.layout = 'Panorama'
    environment.fog.enabled = true
    environment.fog.color = { 199.6, 205.1, 213.7 }
    environment.fog.density = 0.05
    environment.fog.offset = 0
    environment.fog.maxOpacity = 1
    local shadows = environment.shadows
    shadows.enabled, shadows.resolution, shadows.distance = true, 1024, 24
    shadows.fadeDistance, shadows.near = 4, 0.05
    shadows.bias, shadows.normalBias = 0.001, 0.015
    Mesh.create(world, {
        name = 'Ground',
        geometry = Level.tiledPlane(scene, 10),
        size = { 20, 0, 20 },
        surfaceAppearance = {
            colorMap = 'scene://textures/ground.png',
            roughness = 1,
        },
    })
    -- Godot uses an infinite WorldBoundaryShape. The invisible floor covers the
    -- entire playable camera range without stretching the original 20 m mesh.
    world:create('Body3D', {
        name = 'WorldBoundary',
        bodyType = 'Static',
        position = { 0, -1, 0 },
        size = { 20000, 2, 20000 },
        friction = 0,
        restitution = 0,
    })
    -- PlayStation vertex snap with affine textures. Off by default: enable the node in the
    -- Workspace to see it. affine = 0 keeps the floor's four huge vertices readable; raise it
    -- toward 1 for the full affine smear (best on subdivided surfaces).
    world:create('Shader3D', {
        name = 'VertexSnap',
        shaderPath = 'scene://shaders/vertexSnap.glsl',
        enabled = false,
        uniforms = { snapScale = 75, affine = 0 },
    })
    world:create('DirectionalLight3D', {
        name = 'Sun',
        direction = { 0.5, -0.75, -0.43301266 },
        color = { 255, 255, 255 },
        brightness = 0.9,
        castShadow = true,
    })
    local board = world:create('BillboardUI', {
        name = 'WorldSprite',
        position = { 4, 1.03, 0 },
        size = { 0, 2.16, 0, 2.16 },
        sizeMode = 'World3D',
        canvasSize = { 0, 1080, 0, 1080 },
        onTop = false,
        maxDistance = 4000,
    })
    board.ui:create('ImageRect', {
        name = 'Sprite',
        size = { 1, 0, 1, 0 },
        image = 'scene://textures/worldSprite.png',
        backgroundTransparency = 1,
    }, board.ui.content)
    return board
end

return Level
