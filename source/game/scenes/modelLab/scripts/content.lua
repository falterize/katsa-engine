local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')
local Models = require('source.engine.import.models')

local Lab = {}
Lab.__index = Lab

function Lab.new(scene)
    local self = setmetatable({ scene = scene }, Lab)
    scene.world.environment.debug.gizmos.enabled = false
    scene.world.environment.fog.enabled = false
    scene.world.environment.sky.enabled = false
    scene.world.environment.ambient = { 160, 175, 190 }
    require('./lighting.directional').create(scene.world).enabled = true
    scene.world.environment.shadows.enabled = true
    scene:createPhysics({ unitsPerMeter = 20 })
    scene.world.physics = scene.physics
    scene.camera.position = { 0, 65, -105 }
    scene.camera.rotation = { -10, 0, 0 }
    Mesh.create(scene.world, {
        name = 'ModelLabFloor',
        position = { 0, -3, 70 },
        size = { 420, 6, 240 },
        surfaceAppearance = { colorMap = 'stone' },
    })
    local floor = scene.world:create('Body3D', {
        name = 'FloorPhysics',
        bodyType = 'Static',
        position = { 0, -3, 70 },
        collider = { shape = 'Box', size = { 420, 6, 240 } },
    })
    self.model = Models.load('assets/models/characters/xbot.glb', scene.resources)
    Models.instantiate(
        scene.world,
        self.model,
        { name = 'XBot', position = { 35, 0, 50 }, scale = { 0.55, 0.55, 0.55 } }
    )
    self.animator = self.model.animator
    self.animator.debugEnabled = true
    require('./animation.proceduralClips').add(self.model)
    self.track = self.animator:transition('Demo Walk', 0)
    self.markerCount = 0
    self._markerTracks = { [self.track] = true }
    self.track:connect('Marker', function()
        self.markerCount = self.markerCount + 1
    end)
    local hand = self.model.byNodeName['mixamorig:RightHand']
    if hand then
        self.attachment = scene.world:create(
            'Attachment3D',
            { name = 'HandTool', position = { 0, 3, 0 } },
            hand.instance
        )
        Mesh.create(scene.world, {
            name = 'HandToolVisual',
            size = { 4, 12, 4 },
            color = {
                1,
                0.45,
                0.08,
                1,
            },
        }, self.attachment)
        self.sparks = scene.world:create('ParticleEmitter3D', {
            name = 'HandSparks',
            rate = 12,
            speed = { 6, 15 },
            lifetime = { 0.4, 0.7 },
            gravityScale = 0.03,
            startSize = { 1, 2 },
            brightness = 2,
        }, self.attachment)
    end
    self.multi = Models.load('assets/models/examples/cubeTriangle.glb', scene.resources)
    Models.instantiate(
        scene.world,
        self.multi,
        { name = 'CubeTriangle', position = { -65, 0, 55 } }
    )
    self.appearance = scene.world:create('SurfaceAppearance3D', {
        name = 'CubeSurface',
        normalMap = 'assets/textures/materials/normal.png',
        roughnessMap = 'assets/textures/materials/roughness.png',
        metalnessMap = 'assets/textures/materials/metal.png',
        emissionMap = 'assets/textures/materials/emission.png',
        roughness = 0.45,
        metalness = 0.35,
        emissionStrength = 0.25,
    }, self.multi.objects[1])
    self.colliders = {}
    for _, object in ipairs(self.multi.objects) do
        local level = object.name:find('Triangle') and 'Detailed' or 'Convex'
        local body = scene.world:create('Body3D', {
            name = object.name .. 'Physics',
            bodyType = 'Static',
            friction = 0.25,
            restitution = 0.8,
        }, object)
        scene.world:create(
            'Collider3D',
            { shape = 'Geometry', geometrySource = object, collisionLevel = level },
            body
        )
        body:update(0)
        self.colliders[#self.colliders + 1] = body
    end
    return self
end

function Lab:update(dt)
    self.scene.physics:update(dt)
    self.scene.world:updateNodes(dt)
    if self.info then
        self.info.text = 'XBot: 2 source meshes / '
            .. #self.model.objects
            .. ' GPU parts\nProcedural '
            .. self.track.name
            .. ' | markers '
            .. self.markerCount
            .. '\nGreen: bones / purple: attachments\nCube + triangle: independent physics'
    end
end

return Lab
