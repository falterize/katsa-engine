local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')
local Models = require('source.engine.import.models')

local Methods = {}

function Methods:buildMaterials()
    self.effectTarget = self.world.byName['1']
        or self.model and self.model.objects[1]
        or self.world.objects[2]
    if self.effectTarget then
        self.objectEffect = self.world:create('Shader3D', {
            name = 'Wave3D',
            shaderPath = 'assets/shaders/examples/wave3D.glsl',
            enabled = false,
            animated = true,
            uniforms = { waveAmplitude = 0.12, glowColor = { 0.1, 0.7, 1 } },
        }, self.effectTarget)
    end
end

return Methods
