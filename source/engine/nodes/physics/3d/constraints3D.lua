local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Attachment-owned constraint endpoints; backend joints never own scene lifetime.
local Node = require('../../core.baseNode')
local bodyOf = require('source.engine.physics.bodyOf')
local M = require('source.engine.math.math3d')
local A = require('source.engine.math.affine')
local Inputs = require('source.engine.physics.3d.constraints.inputs')
local Settings = require('source.engine.physics.3d.constraints.settings')
local Distance = require('source.engine.physics.3d.constraints.distance')

local settingFields = {
    'lowerLimit',
    'upperLimit',
    'motorSpeed',
    'motorForce',
    'frequency',
    'dampingRatio',
    'allowCollision',
    'breakForce',
    'breakTorque',
}
local C = Node.define('Constraint3D', 'Node')
C.kind = 'Spherical'
C.propertySchema = {
    attachment0 = { kind = 'node' },
    attachment1 = { kind = 'node' },
    status = { readOnly = true },
    length = { min = 0 },
    stiffness = { min = 0 },
    damping = { min = 0 },
    lowerLimit = {},
    upperLimit = {},
    motorSpeed = {},
    motorForce = { min = 0 },
    frequency = { min = 0 },
    dampingRatio = { min = 0 },
    allowCollision = {},
    breakForce = { min = 0 },
    breakTorque = { min = 0 },
    translationLower = {},
    translationUpper = {},
    rotationLower = {},
    rotationUpper = {},
}
for _, key in ipairs({ 'length', 'stiffness', 'damping' }) do
    C.propertySchema[key].visibleWhen = function(node)
        return key == 'length' and (node.kind == 'Rope' or node.kind == 'Spring')
            or node.kind == 'Spring'
    end
end
for _, key in ipairs({ 'translationLower', 'translationUpper', 'rotationLower', 'rotationUpper' }) do
    C.propertySchema[key].visibleWhen = function(node)
        return node.className == 'GenericConstraint3D'
    end
end

function C.initialize(self)
    self.length = self.length or 30
    self.stiffness = self.stiffness or 15
    self.damping = self.damping or 2
    self.lowerLimit = self.lowerLimit or -45
    self.upperLimit = self.upperLimit or 45
    self.motorSpeed = self.motorSpeed or 0
    self.motorForce = self.motorForce or 0
    self.frequency = self.frequency or 0
    self.dampingRatio = self.dampingRatio or 0.7
    self.breakForce = self.breakForce or 0
    self.breakTorque = self.breakTorque or 0
    self.translationLower = self.translationLower or { 0, 0, 0 }
    self.translationUpper = self.translationUpper or { 0, 0, 0 }
    self.rotationLower = self.rotationLower or { 0, 0, 0 }
    self.rotationUpper = self.rotationUpper or { 0, 0, 0 }
    self.status = 'Waiting for attachments'
end

function C.mount(world, properties, parent)
    assert(world.physics, 'Constraints require a Physics world')
    local self = Node.new(properties.className or 'Constraint3D', properties, parent)
    self._world = world
    world.physics.constraints = world.physics.constraints or {}
    table.insert(world.physics.constraints, self)
    self:onDestroy(function()
        self:releaseJoint()
        for i, n in ipairs(world.physics.constraints) do
            if n == self then
                table.remove(world.physics.constraints, i)
                break
            end
        end
    end)
    return self
end

function C:releaseJoint(preserveInputs)
    if self.joint then
        self._world.physics.world:removeJoint(self.joint)
        self.joint = nil
    end
    self._jointKey = nil
    self._distanceLinkKey = nil
    if not preserveInputs then
        self._constraintInputs = nil
    end
end

local function endpoint(attachment, cache)
    if not attachment or attachment.destroyed or not attachment:isA('Attachment3D') then
        return
    end
    local owner = attachment.parent
    while owner and not bodyOf(owner) do
        owner = owner.parent
    end
    if not owner or bodyOf(owner).destroyed then
        return
    end
    local world = attachment:getWorldMatrix()
    cache.inverse = A.inverse(owner:getWorldMatrix(), cache.inverse)
    cache.localFrame = M.multiply(cache.inverse, world, cache.localFrame)
    local localFrame = cache.localFrame
    local x, y, z = M.normalize(localFrame[1], localFrame[5], localFrame[9])
    local ux, uy, uz = M.normalize(localFrame[2], localFrame[6], localFrame[10])
    cache.position, cache.axis, cache.up = cache.position or {}, cache.axis or {}, cache.up or {}
    local p, axis, up = cache.position, cache.axis, cache.up
    p[1], p[2], p[3] = localFrame[4], localFrame[8], localFrame[12]
    axis[1], axis[2], axis[3] = x, y, z
    up[1], up[2], up[3] = ux, uy, uz
    return bodyOf(owner), p, axis, up, world
end

function C:step(dt)
    if self.destroyed then
        return
    end
    if self.enabled == false then
        self:releaseJoint()
        self._previousAnchor0, self._previousAnchor1 = nil, nil
        self.status = 'Disabled'
        return
    end
    self._endpoint0, self._endpoint1 = self._endpoint0 or {}, self._endpoint1 or {}
    local a, p0, x0, y0, m0 = endpoint(self.attachment0, self._endpoint0)
    local b, p1, x1, y1, m1 = endpoint(self.attachment1, self._endpoint1)
    if not a or not b or a == b then
        self:releaseJoint()
        self.status = 'Waiting for two distinct bodies'
        return
    end
    assert(
        a.space == self._world.physics and b.space == a.space,
        'Attachments must belong to this physics world'
    )
    if self.kind == 'Rope' or self.kind == 'Spring' then
        Distance.step(self, a, b, p0, p1, m0, m1, dt)
        return
    end
    local inputs = Inputs.begin(self, a, b, self.kind)
    inputs:vector(p0)
    inputs:vector(p1)
    inputs:vector(x0)
    inputs:vector(x1)
    inputs:vector(y0)
    inputs:vector(y1)
    inputs:vector(self.translationLower)
    inputs:vector(self.translationUpper)
    inputs:vector(self.rotationLower)
    inputs:vector(self.rotationUpper)
    for _, name in ipairs(settingFields) do
        inputs:value(self[name])
    end
    local key = inputs:finish()
    if key == self._jointKey then
        return
    end
    local settings = Settings.build(self, p0, p1, x0, x1, y0, y1)
    local kind = self.kind
    local candidate = self._world.physics:_createJoint(kind, a, b, settings)
    self:releaseJoint(true)
    self.joint = candidate
    candidate.ownerConstraint = self
    self._jointKey = key
    self.status = 'Active'
end
require('./constraintTypes').register(C)

return C
