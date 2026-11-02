local pairs = require('../../math.array').pairs
local Math = require('../../math.math3d')
local Validate = require('../../core.validate')
local Casters = require('./shadowCasters')
local Batches = require('../pipeline.batches')
local Cascades = require('./directionalCascades')
local ShadowCache = require('./shadowCache')
local Schedule = require('./shadowSchedule')
local Receivers = require('./shadowReceivers')
local Frusta = require('./shadowFrusta')

local Shadows = {}
Shadows.__index = function(self, key)
    if key == 'shader' then
        if rawget(self, '_released') or self.resources.released then
            return nil
        end
        local shader =
            self.resources:own(katsa.graphics.newShader('assets/shaders/engine/shadow.glsl'))
        rawset(self, key, shader)
        return shader
    end
    return Shadows[key]
end

function Shadows.new(resources)
    local self = setmetatable({
        resources = resources,
        matrices = {},
        view = Math.identity(),
        projection = Math.identity(),
        position = {},
        direction = {},
        parameters = {},
        tile = {},
        nextUpdate = 0,
        generation = 0,
        drawCalls = 0,
        batches = Batches.new({ shadow = true }),
        faceBatches = {},
        faceOwners = {},
        casters = {},
        casterTests = 0,
        casterSubmissions = 0,
        atlasAllocations = 0,
        planes = {},
        texelSize = {},
        atlasSize = {},
        lightData = {},
        lightProjectionPosition = {},
        lightProjectionDirection = {},
        lightFade = {},
        assignments = {},
        cache = ShadowCache.new(),
        tasks = {},
        updatedFaces = 0,
        updatedLights = 0,
    }, Shadows)
    for i = 1, Cascades.matrixRows do
        self.matrices[i] = Math.identity()
    end
    for i = 1, 32 do
        self.lightData[i] = { -1, 0, 0, 0 }
        self.lightFade[i] = 1
        self.lightProjectionPosition[i] = { 0, 0, 0, 1 }
        self.lightProjectionDirection[i] = { 0, 0, 1, 0.5 }
    end
    self.matrixPixels = katsa.image.newImageData(4, Cascades.matrixRows, 'rgba32f')
    self.matrixTexture = katsa.graphics.newImage(self.matrixPixels)
    self.matrixTexture:setFilter('nearest', 'nearest')
    return self
end
require('./shadowAtlas').install(Shadows)
require('./shadowDepthPass').install(Shadows)
require('./shadowUpdate').install(Shadows)
require('./shadowBindings').install(Shadows)

function Shadows:release()
    self._released = true
    self.cache.objects, self.assignments, self.residents = {}, {}, {}
    self.matrixTexture:release()
    self.matrixPixels:release()
    local released = {}
    for _, batches in pairs(self.faceBatches) do
        batches:release()
        released[batches] = true
    end
    if not released[self.batches] then
        self.batches:release()
    end
    self.faceBatches, self.faceOwners = {}, {}
    if self.depth then
        self.depth:release()
        self.depth = nil
    end
end

return Shadows
