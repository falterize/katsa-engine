local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local Mesh = require('source.engine.composition.mesh')
local copy = require('source.engine.animation.bindings').copy

-- All effect presets and lab behavior belong to the example, not the engine.
local Lab = {}
Lab.__index = Lab
local presets = {
    Smoke = {
        rate = 25,
        lifetime = { 3, 5 },
        speed = { 6, 12 },
        startSize = { 8, 14 },
        _size = { 1, 2, 3 },
        _c0 = { 0.45, 0.48, 0.52 },
        _c1 = { 0.35, 0.38, 0.42 },
        _c2 = { 0.2, 0.22, 0.25 },
        _alpha = { 0.35, 0.6, 1 },
        acceleration = { 0, 3, 0 },
        drag = 0.6,
    },
    Dust = {
        rate = 22,
        shape = 'Box',
        shapeSize = { 25, 1, 25 },
        lifetime = { 1, 2 },
        speed = { 6, 14 },
        spread = 70,
        startSize = { 3, 7 },
        _c0 = { 0.65, 0.47, 0.25 },
        _c1 = { 0.5, 0.38, 0.2 },
        _c2 = { 0.3, 0.2, 0.1 },
        gravityScale = 0.03,
        drag = 1.5,
    },
    Sparks = {
        rate = 28,
        lifetime = { 1, 2 },
        speed = { 35, 70 },
        spread = 50,
        startSize = { 1, 3 },
        _size = { 1, 0.7, 0 },
        _c0 = { 1, 1, 0.4 },
        _c1 = { 1, 0.4, 0.05 },
        _c2 = { 0.8, 0.05, 0 },
        blendMode = 'Add',
        gravityScale = 0.25,
        collisionEnabled = true,
        restitution = 0.6,
        orientation = 'Velocity',
    },
    Fire = {
        rate = 45,
        lifetime = { 0.7, 1.5 },
        speed = { 12, 22 },
        startSize = { 8, 15 },
        _size = { 1, 0.8, 0.1 },
        _c0 = { 1, 0.8, 0.12 },
        _c1 = { 1, 0.18, 0.02 },
        _c2 = { 0.25, 0.04, 0 },
        blendMode = 'Add',
        atlasEnabled = true,
        texture = 'assets/textures/particles/atlas.png',
        atlasFPS = 14,
        drag = 0.4,
    },
    Attraction = {
        rate = 35,
        shape = 'Sphere',
        surfaceOnly = true,
        shapeSize = { 80, 80, 80 },
        lifetime = { 2, 4 },
        speed = { 0, 0 },
        startSize = { 2, 4 },
        _c0 = { 0.1, 0.8, 1 },
        _c1 = { 0.3, 0.3, 1 },
        _c2 = { 1, 0.2, 0.8 },
        blendMode = 'Add',
        attractionEnabled = true,
        attractionStrength = 80,
        attractionSoftening = 40,
        attractionPoint = { 120, 40, 80 },
        drag = 0.2,
    },
}

local points = function(a, b, c)
    return { { time = 0, value = a }, { time = 0.5, value = b }, { time = 1, value = c } }
end
for _, preset in pairs(presets) do
    preset.lifetimeBindings = {}
    if preset._size then
        preset.lifetimeBindings.size = points(unpack(preset._size))
    end
    if preset._alpha then
        preset.lifetimeBindings.transparency = points(unpack(preset._alpha))
    end
    if preset._c0 then
        preset.lifetimeBindings.color =
            points(preset._c0, preset._c1 or preset._c0, preset._c2 or preset._c0)
    end
    preset._size, preset._alpha, preset._c0, preset._c1, preset._c2 = nil, nil, nil, nil, nil
end
local names = { 'Smoke', 'Dust', 'Sparks', 'Fire', 'Attraction' }

function Lab.new(scene)
    local self = setmetatable({ scene = scene, emitters = {} }, Lab)
    scene.world.environment.ambient = { 170, 170, 180 }
    scene.world.environment.debug.gizmos.enabled = false
    scene.world.environment.fog.enabled = false
    scene.world.environment.shadows.enabled = false
    scene:createPhysics({ unitsPerMeter = 20 })
    scene.world.physics = scene.physics
    Mesh.create(scene.world, {
        name = 'ParticleFloor',
        position = { 0, -5, 70 },
        size = { 500, 10, 400 },
        surfaceAppearance = { colorMap = 'stone' },
    })
    local floor = scene.world:create(
        'Body3D',
        { name = 'FloorBody', bodyType = 'Static', position = { 0, -5, 70 } }
    )
    scene.world:create('Collider3D', { shape = 'Box', size = { 500, 10, 400 } }, floor)
    scene.camera.position, scene.camera.rotation = { 0, 95, -145 }, { -12, 0, 0 }
    scene.camera.drawDistance = 1200
    for i, name in ipairs(names) do
        local support = scene.world:create(
            'Attachment3D',
            { name = name .. 'Anchor', position = { (i - 3) * 60, 8, 80 } }
        )
        if name == 'Attraction' then
            support.position[2] = 40
        end
        local props = { name = name, position = { 0, 0, 0 }, seed = i }
        for key, value in pairs(presets[name]) do
            props[key] = copy(value)
        end
        self.emitters[i] = scene.world:create('ParticleEmitter3D', props, support)
        local board = scene.world:create('BillboardUI', {
            name = name .. 'Label',
            size = { 0, 90, 0, 24 },
            canvasSize = { 0, 90, 0, 24 },
            position = { 0, -4, 0 },
            onTop = true,
        }, support)
        board.ui:text({
            size = { 1, 0, 1, 0 },
            text = name,
            fontSize = 13,
            backgroundColor = { 0.02, 0.05, 0.1 },
            backgroundTransparency = 0.25,
        }, board.ui.content)
        Mesh.create(scene.world, {
            name = name .. 'Stand',
            position = { (i - 3) * 60, 2, 80 },
            size = { 20, 4, 20 },
            color = { 0.2, 0.35, 0.5, 1 },
        })
    end
    self.selected = 1
    self.emitter = self.emitters[1]
    return self
end

function Lab:restorePreset(emitter)
    emitter:clear()
    local seed = emitter.seed
    for key, value in pairs(require('source.engine.nodes').getClass('ParticleEmitter3D').defaults) do
        emitter[key] = copy(value)
    end
    for key, value in pairs(presets[emitter.name]) do
        emitter[key] = copy(value)
    end
    require('source.engine.particles.lifetime').configure(emitter, emitter.lifetimeBindings)
    emitter.lifetimeBindings = nil
    emitter.seed = seed
    emitter.enabled = true
end

function Lab:update(dt)
    self.scene.physics:update(dt)
    self.scene.world:updateNodes(dt)
    if self.status then
        self.scene.package:require('scripts.ui.panels.controls').update(self)
    end
end

return Lab
