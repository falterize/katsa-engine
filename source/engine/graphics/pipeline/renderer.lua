local Lights = require('../../world.lights')
local Gizmos = require('../debug.gizmos')
local Geometry = require('../geometry.primitives')
local M = require('../../math.math3d')
local Batches = require('./batches')
local bit = require('bit')
local Shadows = require('../shadows.shadows')
local Occlusion = require('../occlusion.occlusion')
local Triangles = require('../debug.triangles')
-- Renderer facade owns construction/lifetime; passes install direct methods.
local Renderer = {}
local shaderPaths = {
    shader = 'assets/shaders/engine/world.glsl',
    wireShader = 'assets/shaders/engine/wireframe.glsl',
}
Renderer.__index = function(self, key)
    local path = shaderPaths[key]
    if path then
        if rawget(self, '_released') or self.resources.released then
            return nil
        end
        local source = key == 'shader' and require('source.engine.graphics.shaderSource').read(path)
            or path
        local shader = self.resources:own(katsa.graphics.newShader(source))
        rawset(self, key, shader)
        return shader
    end
    return Renderer[key]
end

function Renderer.new(resources)
    local sky = resources:own(katsa.graphics.newShader('assets/shaders/engine/sky.glsl'))
    local quad = Geometry.quad()
    resources:own(quad.mesh)
    return setmetatable({
        resources = resources,
        sky = sky,
        quad = quad,
        lights = Lights.new(),
        shadows = Shadows.new(resources),
        gizmos = Gizmos.new(),
        batches = Batches.new(),
        visible = {},
        surfaceReceivers = {},
        opaque = {},
        transparent = {},
        top = {},
        stats = {},
        tint = {},
        ambient = {},
        fogColor = {},
        fogSettings = {},
        skyRight = {},
        skyUp = {},
        skyForward = {},
        skySize = {},
        skyInset = {},
        skyTint = {},
        frame = 0,
        shaderFrames = {},
        depthPrepass = true,
        occlusionCulling = false,
        occlusionMaxOccluders = 24,
        occlusionTriangleBudget = 192,
        occlusionMinArea = 256,
        renderDensity = math.max(1, math.min(3, katsa.graphics.getDPIScale())),
        msaa = require('source.engine.graphics.quality.renderQuality').defaultSamples(),
        maxMeshDistance = 0, -- 0 keeps camera-frustum-only mesh culling.
        maxRenderPixels = require('source.engine.graphics.quality.renderQuality').defaultPixels(),
        maxRenderBytes = 402653184,
    }, Renderer)
end
require('./renderTargets').install(Renderer)
require('./renderPreparation').install(Renderer)
require('./renderFrame').install(Renderer)

function Renderer:invalidate()
    self._renderInvalidationRevision = (self._renderInvalidationRevision or 0) + 1
end

function Renderer:release()
    self._released = true
    require('source.engine.graphics.pipeline.depthPrepass').release(self)
    require('source.engine.graphics.occlusion.triangles').release(self.occlusionState)
    self.occlusionState, self.occlusionMeshes = nil, nil
    self._frameCache = nil
    if self.world and self.world._renderDependencyOwner == self then
        self.world._renderDependencyOwner, self.world._renderDependencyRevision = nil, nil
    end
    require('source.engine.graphics.debug.wireframe').release(self)
    self.batches:release()
    self.shadows:release()
    if self.canvas then
        self.canvas:release()
        self.depth:release()
        self.canvas = nil
        self.depth = nil
    end
end
require('./renderBindings').install(Renderer)
require('./renderItems').install(Renderer)
return Renderer
