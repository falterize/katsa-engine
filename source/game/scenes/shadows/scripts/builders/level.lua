local object = require('scene.scripts.builders.object')

local Shadows = {}

function Shadows.build(self, scene)
    scene.world.lights[1].brightness = 0.25
    scene.world.lights[1].forceUpdate = true
    scene.world.environment.ambient = { 20, 24, 30 }
    -- This lab keeps all three lights selected while the camera moves.
    scene.world.environment.lightSettings.cullInvisible = false
    self.directionalShadow = scene.world:create('DirectionalLight3D', {
        name = 'DirectionalSun',
        enabled = false,
        rotation = { 63.434948822922, 53.130102354156, 0 },
        brightness = 1.2,
        castShadow = true,
    })
    self.directionalFill = scene.world:create('DirectionalLight3D', {
        name = 'DirectionalFill',
        rotation = { 50, -50, 0 },
        color = { 150, 180, 255 },
        brightness = 0.5,
        enabled = false,
        castShadow = true,
    })
    self.shadowMotion = false
    scene.world.environment.shadows.enabled = true
    scene.world.environment.shadows.distance = 240
    self.shadowCube = object.create(
        scene,
        'ShadowCaster',
        { 0, 25, 55 },
        { 32, 50, 32 },
        { color = { 0.35, 0.65, 1, 1 } },
        { type = 'Kinematic' }
    )
    object.create(
        scene,
        'TallPillar',
        { -65, 40, 110 },
        { 25, 80, 25 },
        { surfaceAppearance = { colorMap = 'bricks' } },
        { type = 'Static' }
    )
    object.create(
        scene,
        'BallCaster',
        { 70, 28, 80 },
        { 40, 40, 40 },
        { kind = 'sphere' },
        { type = 'Static', collider = { shape = 'Sphere', radius = 20 } }
    )
    self.shadowSpot = scene.world:create('SpotLight3D', {
        name = 'ShadowSpot',
        position = { 0, 100, -20 },
        rotation = { 40, 0, 0 },
        range = 300,
        radius = 240,
        brightness = 1.5,
        castShadow = true,
        forceUpdate = true,
    })
    self.shadowPoint = scene.world:create('PointLight3D', {
        name = 'ShadowPoint',
        position = { 60, 100, 60 },
        range = 300,
        radius = 5,
        brightness = 1.5,
        castShadow = true,
        forceUpdate = true,
        color = { 255, 220, 185 },
    })
end

return Shadows
