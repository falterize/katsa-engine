local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local object = require('scene.scripts.builders.object')

local Demo = {}
Demo.__index = Demo

function Demo.new(scene)
    local zone = 'nodes'
    local self = setmetatable({
        scene = scene,
        zone = zone,
    }, Demo)
    scene:createPhysics({ unitsPerMeter = 20 })
    scene.world.physics = scene.physics
    scene.camera.position = { 0, 65, -160 }
    scene.camera.rotation = { -12, 0, 0 }
    scene.camera.drawDistance = 1000
    scene.world.environment.fog.enabled = false
    scene.world.environment.debug.gizmos.enabled = false
    scene.world.environment.ambient = { 105, 110, 125 }
    object.create(
        scene,
        'Ground',
        { 0, -10, 120 },
        { 500, 20, 650 },
        { surfaceAppearance = { colorMap = 'dirt' } },
        { type = 'Static', friction = 0.8 }
    )
    scene.world:addLight({
        name = 'Warm',
        position = { 0, 100, 60 },
        range = 400,
        radius = 30,
        brightness = 2,
        color = { 255, 225, 190 },
    })
    require('scene.scripts.builders.level').build(self, scene)
    return self
end

for _, name in ipairs({ 'behaviors.simulation' }) do
    for key, method in pairs(require('scene.scripts.' .. name)) do
        Demo[key] = method
    end
end

return Demo
