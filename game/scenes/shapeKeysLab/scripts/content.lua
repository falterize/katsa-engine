local Models = require('source.engine.import.models')
local Mesh = require('source.engine.composition.mesh')

-- Shape keys (Blender) arrive as glTF morph targets. assets/models/blob.glb is produced by
-- tools/import/makeShapeKeyDemo.py (the same script writes a .blend when run inside Blender).
-- Every shape has a slider; "Wave" animates all of them from code to show that scripts control the
-- weights at any time.
local Lab = {}
Lab.__index = Lab

function Lab.new(scene)
    local self = setmetatable({ scene = scene, time = 0, wave = false }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    world.environment.fog.enabled = false
    world.environment.ambient = { 90, 96, 110 }
    world:create('DirectionalLight3D', {
        name = 'Sun',
        rotation = { 50, 25, 0 },
        color = { 255, 238, 210 },
        brightness = 1.1,
    })
    Mesh.create(world, {
        name = 'Floor',
        kind = 'plane',
        position = { 0, -3, 0 },
        size = { 30, 0, 30 },
        color = { 0.2, 0.22, 0.28, 1 },
    })
    local model = Models.load('scene://models/blob.glb', scene.resources)
    self.model = model
    local objects =
        Models.instantiate(world, model, { name = 'Blob', position = { 0, 0, 0 }, size = { 2, 2, 2 } })
    for _, object in ipairs(objects) do
        if object.getBlendShapeCount and object:getBlendShapeCount() > 0 then
            self.mesh = object
            break
        end
    end
    self.names = self.mesh and self.mesh:getBlendShapes() or {}
    self.values = {}
    scene.camera.position = { 0, 1, -9 }
    scene.camera.rotation = { 0, 0, 0 }
    return self
end

function Lab:setShape(name, value)
    self.values[name] = value
    if self.mesh then
        self.mesh:setBlendShapeValue(name, value)
    end
end

function Lab:update(dt)
    self.time = self.time + dt
    if self.wave and self.mesh then
        for index, name in ipairs(self.names) do
            local value = 0.5 + 0.5 * math.sin(self.time * 1.5 + index * 1.7)
            self:setShape(name, value)
            if self.sliders and self.sliders[name] then
                self.sliders[name].value = value
            end
        end
    end
    self.scene.world:updateNodes(dt)
end

return Lab
