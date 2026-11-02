local Node = require('../core.baseNode')
local ParticleSettings = require('../../particles.settings')
local Debug2DSettings = require('../../physics.2d.debugSettings')

local C = Node.define('Environment', 'Node')
C.propertySchema = { systemLayers = { kind = 'bindings' } }

function C.initialize(self)
    self.particles = self.particles or ParticleSettings.create(self._dimension or 3)
    if self._dimension == 2 then
        self.ambient, self.brightness = self.ambient or { 255, 255, 255 }, self.brightness or 1
        self.debug = self.debug or { orientation2D = false }
        self.debug.physics = self.debug.physics or Debug2DSettings.create(false)
        return
    end
    self.debug = self.debug or {}
    self.debug.physics = self.debug.physics
        or {
            enabled = false,
            wireframe = true,
            drawShapes = true,
            drawAabbs = false,
            drawBases = false,
            drawContacts = false,
            drawContactBases = false,
            drawPairs = false,
            drawJoints = true,
            drawJointLimits = false,
            drawBvh = false,
        }
    self.debug.physics._settingsKind = 'PhysicsDebug'
    self.sun = nil
    self.debug.bones = self.debug.bones == true
    self.debug.wireframe = self.debug.wireframe == true
    self.debug.gizmos = self.debug.gizmos
        or self.gizmos
        or { enabled = true, updateHz = 8, activeOnly = true, maxDistance = 0 }
    -- Keep the previous API as a shared-table compatibility alias.
    self.gizmos = self.debug.gizmos
    self.systemLayers = self.systemLayers
        or {
            lighting = 'Default3D',
            shadows = 'Default3D',
            fog = 'Default3D',
            toneMapping = 'Default3D',
        }
    -- Global texture filtering is intentionally unsupported.
    self.pixelate = nil
    self.render = self.render
        or {
            surfaceBlendResolution = 256,
            renderDensity = math.max(1, math.min(3, katsa.graphics.getDPIScale())),
            msaa = require('source.engine.graphics.quality.renderQuality').defaultSamples(),
            maxMeshDistance = 0,
            maxRenderPixels = require('source.engine.graphics.quality.renderQuality').defaultPixels(),
            maxRenderBytes = 402653184,
        }
    if self.render.depthPrepass == nil then
        self.render.depthPrepass = true
    end
    if self.render.occlusionCulling == nil then
        self.render.occlusionCulling = false
    end
    self.render.occlusionMaxOccluders = self.render.occlusionMaxOccluders or 24
    self.render.occlusionTriangleBudget = self.render.occlusionTriangleBudget or 192
    self.render.occlusionMinArea = self.render.occlusionMinArea or 256
    -- Direct uniform-slot iteration avoids driver-dependent bit/index overhead on GLES.
    self.render.lightLoop = self.render.lightLoop or 'Direct'
    if self.render.frameCache == nil then
        self.render.frameCache = true
    end
end

function C.mount(context, properties, parent)
    local plane = parent and parent:isA('World2D') and parent or nil
    assert(
        parent and (plane or parent == context.root),
        'Environment belongs directly to its world'
    )
    local owner = plane or context
    assert(not owner.environment, 'Each world has exactly one required Environment')
    properties.name = 'Environment'
    properties._dimension = plane and 2 or 3
    properties._environmentOwner = parent
    properties._settingsOwner = owner
    properties._ownerUI = plane
    local node = Node.new('Environment', properties, parent)
    owner.environment = node
    if plane then
        owner.debug = node.debug
    else
        context.lighting = node
    end
    return node
end

function C:destroy()
    assert(
        self.destroyed
            or self.parent and self.parent._destroying
            or self._ownerUI and self._ownerUI._destroying,
        'Environment is required; configure it instead of destroying it'
    )
    return Node.destroy(self)
end

return C
