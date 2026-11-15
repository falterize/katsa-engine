local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')

local Scene = {}
Scene.__index = Scene

function Scene.new(scene)
    scene.camera.position = { 0, 45, -120 }
    scene.camera.rotation = { -12, 0, 0 }
    scene.camera.drawDistance = 900
    local settings = scene.world.environment
    settings.lightSettings.maxActiveLights = 32
    settings.gizmos.enabled = false
    Mesh.create(scene.world, {
        name = 'Floor',
        kind = 'plane',
        position = { 0, -12, 100 },
        size = { 800, 0, 800 },
        surfaceAppearance = { colorMap = 'dirt' },
    })
    local stress = scene.settings.stress or {}
    local side = stress.side or 20
    for x = 1, side do
        for z = 1, side do
            Mesh.create(scene.world, {
                name = 'Cube' .. x .. '.' .. z,
                position = { (x - (side + 1) / 2) * 24, 0, z * 24 - 60 },
                size = { 14, 18, 14 },
                surfaceAppearance = { colorMap = (x + z) % 2 == 0 and 'stone' or 'bricks' },
            })
        end
    end
    local count = stress.lights or 64
    for i = 1, count do
        scene.world:addLight({
            name = 'Stress' .. i,
            type = i % 4 == 0 and 'SpotLight3D' or 'PointLight3D',
            position = { ((i - 1) % 8 - 3.5) * 42, 30, math.floor((i - 1) / 8) * 42 },
            rotation = { 70, 0, 0 },
            range = 150,
            radius = 25,
            brightness = 1.5,
            color = { 100 + (i * 79) % 155, 100 + (i * 41) % 155, 100 + (i * 23) % 155 },
        })
    end
    return setmetatable({ scene = scene }, Scene)
end

function Scene:update(dt)
    self.scene.world:updateNodes(dt)
end

return Scene
