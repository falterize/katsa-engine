local Mesh = require('source.engine.composition.mesh')

local Lab = {}
Lab.__index = Lab

function Lab.new(scene)
    local self = setmetatable({ scene = scene }, Lab)
    local w = scene.world
    scene:createPhysics({ unitsPerMeter = 20, interpolate = true })
    w.physics = scene.physics
    scene.camera.position = { 0, 80, -165 }
    scene.camera.rotation = { -12, 0, 0 }
    scene.camera.drawDistance = 1500
    local e = w.environment
    e.debug.gizmos.enabled = false
    e.sky.enabled = true
    require('scene.scripts.lighting.directional').create(scene.world).enabled = true
    require('scene.scripts.lighting.directional').create(scene.world).brightness = 1.6
    e.ambient = { 30, 36, 50 }
    e.exposure = 1.2
    e.fog.enabled = true
    e.fog.density = 0.001
    e.fog.offset = 160
    e.fog.maxOpacity = 0.4
    e.shadows.enabled = true
    e.shadows.mode = 'Realistic'
    e.shadows.resolution = 1024
    e.shadows.filterSamples = 9
    e.shadows.distance = 600
    e.shadows.maxUpdateFaces = 64
    e.shadows.updateHz = 60
    e.shadows.softnessLimit = 16
    e.render.renderDensity = 3
    e.render.msaa = 8
    e.render.maxRenderPixels = 16777216
    e.render.maxRenderBytes = 536870912
    e.render.surfaceBlendResolution = 512
    e.lightSettings.maxActiveLights = 32
    local floor = w:create('Body3D', {
        name = 'GalleryFloor',
        bodyType = 'Static',
        position = { 0, -5, 90 },
        collider = { shape = 'Box', size = { 420, 10, 380 } },
    })
    Mesh.create(w, {
        name = 'GalleryFloorVisual',
        size = { 420, 10, 380 },
        surfaceAppearance = {
            colorMap = 'stone',
            normalMap = 'assets/textures/materials/normal.png',
            roughness = 0.15,
            metalness = 0.6,
        },
    }, floor)
    for i = 1, 12 do
        Mesh.create(w, {
            name = 'MaterialSphere' .. i,
            kind = 'sphere',
            position = { ((i - 1) % 4 - 1.5) * 55, 18, math.floor((i - 1) / 4) * 60 + 30 },
            size = { 30, 30, 30 },
            surfaceAppearance = {
                colorMap = 'bricks',
                normalMap = 'assets/textures/materials/normal.png',
                roughness = 0.05 + (i - 1) / 12 * 0.8,
                metalness = (i % 3) / 2,
                emissionColor = { 0.1, 0.4, 1 },
                emissionStrength = 0.1,
            },
        }, w.root)
    end
    for i = 1, 32 do
        w:create('PointLight3D', {
            name = 'GalleryLight' .. i,
            position = {
                math.cos(i * math.pi / 16) * 110,
                35 + (i % 4) * 18,
                90 + math.sin(i * math.pi / 16) * 110,
            },
            range = 150,
            brightness = 0.5,
            color = { 70 + (i * 47) % 185, 80 + (i * 31) % 175, 110 + (i * 19) % 145 },
            castShadow = true,
        })
    end
    local shelter = w:create('Body3D', {
        name = 'ParticleShelter',
        bodyType = 'Static',
        position = { 0, 70, 90 },
        collider = { shape = 'Box', size = { 95, 8, 95 } },
    })
    Mesh.create(
        w,
        { name = 'ShelterVisual', size = { 95, 8, 95 }, color = { 0.25, 0.3, 0.4 } },
        shelter
    )
    self.emitter = w:create('ParticleEmitter3D', {
        name = 'ShadowCollisionRain',
        position = { 0, 110, 90 },
        shape = 'Box',
        shapeSize = { 130, 1, 100 },
        rate = 140,
        maxParticles = 1200,
        lifetime = { 2, 3 },
        speed = { 20, 40 },
        direction = { 0, -1, 0 },
        gravityScale = 0.2,
        startSize = { 4, 7 },
        unlit = false,
        brightness = 1,
        castShadow = true,
        receiveShadow = true,
        shadowMaxParticles = 512,
        shadowGroup = 'Default',
        collisionEnabled = true,
        restitution = 0.6,
    })
    self.emitter:emit(120)
    self.dust = w:create('ParticleEmitter3D', {
        name = 'ShadowedDust',
        position = { 0, 15, 90 },
        shape = 'Box',
        shapeSize = { 70, 8, 65 },
        rate = 40,
        maxParticles = 160,
        lifetime = { 1.5, 2.5 },
        speed = { 8, 15 },
        startSize = { 4, 7 },
        gravityScale = 0.1,
        unlit = false,
        castShadow = true,
        receiveShadow = true,
        collisionEnabled = true,
        restitution = 0.5,
        shadowMaxParticles = 128,
    })
    self.dust:emit(40)
    self.material = w:create('Shader3D', {
        name = 'GalleryTint',
        shaderPath = 'assets/shaders/examples/tint3D.glsl',
        zIndex = 1,
        uniforms = { tintEffect = { 1, 1, 1 } },
    }, w.root)
    return self
end

function Lab:update(dt)
    self.scene.physics:update(dt)
    self.scene.world:updateNodes(dt)
end

return Lab
