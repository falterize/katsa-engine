local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')
local Models = require('source.engine.import.models')

local Scene = {}
Scene.__index = Scene

function Scene.new(scene)
    scene.camera.position = { 0, 18, -75 }
    scene.world.environment.fog.enabled = false
    scene.world.environment.debug.gizmos.enabled = false
    scene.world.environment.ambient = { 130, 130, 145 }
    Mesh.create(scene.world, {
        name = 'Floor',
        kind = 'plane',
        position = { 0, -10, 40 },
        size = { 200, 0, 200 },
        surfaceAppearance = { colorMap = 'dirt' },
    })
    local obj = Models.load('assets/models/examples/pyramid.obj', scene.resources)
    Models.instantiate(
        scene.world,
        obj,
        { name = 'OBJ', position = { -28, -10, 35 }, size = { 20, 20, 20 } }
    )
    scene.model = Models.load('assets/models/examples/animated.glb', scene.resources)
    Models.instantiate(
        scene.world,
        scene.model,
        { name = 'GLB', position = { 25, 0, 35 }, size = { 18, 18, 18 } }
    )
    scene.model:play(1)
    local converted = Models.load('assets/models/examples/converted.glb', scene.resources)
    Models.instantiate(
        scene.world,
        converted,
        { name = 'FBX', position = { 0, 0, 85 }, size = { 10, 10, 10 } }
    )
    scene.world:addLight({
        name = 'ModelLight',
        type = 'PointLight3D',
        position = { 0, 45, 5 },
        range = 180,
        radius = 10,
        color = { 255, 220, 175 },
    })
    Mesh.create(scene.world, {
        name = 'Glass',
        position = { 0, 2, 5 },
        size = { 18, 24, 1 },
        color = { 0.3, 0.7, 1, 0.3 },
        blend = true,
    })
    local b = require('source.engine.ui.spatial.billboard').new(scene.world, {
        name = 'Attached',
        adornee = scene.model.objects[1],
        position = { 0, 28, 0 },
        size = { 0, 360, 0, 100 },
        canvasSize = { 0, 360, 0, 100 },
        sizeMode = 'Screen',
        onTop = false,
        maxDistance = 250,
    })
    do
        local node = b.ui:create('Button', {
            position = { 0, 0, 0, 0 },
            size = { 0, 360, 0, 100 },

            backgroundColor = { 0.15, 0.25, 0.4 },
            backgroundTransparency = 1 - 1,
            text = 'ANIMATED GLB\nTap to play spatial stereo',
            fontSize = 26,
        }, b.ui.content)
        node:connect('press', function()
            scene.audio:play('assets/audio/effects/stereoChime.wav', {
                object = scene.model and scene.model.objects[1],
                minDistance = 30,
                maxDistance = 220,
            })
        end)
    end
    return setmetatable({ scene = scene }, Scene)
end

function Scene:update(dt)
    self.scene.world:updateNodes(dt)
end

return Scene
