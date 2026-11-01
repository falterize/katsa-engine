local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')
local Sequence = require('source.engine.animation.sequence')

local Lab = {}
Lab.__index = Lab

function Lab.new(scene)
    local self = setmetatable({ scene = scene }, Lab)
    scene.world.environment.shadows.enabled = false
    scene.world.environment.debug.gizmos.enabled = false
    scene.camera.position = { 0, 40, -120 }
    scene.camera.rotation = { -12, 0, 0 }
    scene:createPhysics({ unitsPerMeter = 20 })
    scene.world.physics = scene.physics
    self.body = scene.world:create(
        'Body3D',
        { name = 'AnimatedPlatform', bodyType = 'Kinematic', position = { -35, 10, 50 } }
    )
    scene.world:create('Collider3D', { shape = 'Box', size = { 24, 8, 24 } }, self.body)
    Mesh.create(scene.world, {
        name = 'PlatformVisual',
        size = { 24, 8, 24 },
        surfaceAppearance = { colorMap = 'bricks' },
    }, self.body)
    self.ramp = scene.world:create('Ramp', {
        name = 'PreparedMotion',
        mode = 'Animated',
        playbackTime = 2,
        reverses = true,
        repeatCount = -1,
        reverseDelay = 0.25,
        repeatDelay = 0.5,
        interpolation = 'Curve',
        points = {
            { time = 0, value = 0, outgoing = { 0.2, 0 } },
            {
                time = 1,
                value = 1,
                incoming = { 0.8, 1 },
            },
        },
        bindings = {
            position = Sequence.linear({ -35, 10, 50 }, { 35, 30, 50 }),
            rotation = Sequence.linear({ 0, 0, 0 }, { 0, 90, 0 }),
        },
    }, self.body)
    return self
end

function Lab:update(dt)
    self.scene.world:updateNodes(dt)
    self.scene.physics:update(dt)
end

return Lab
