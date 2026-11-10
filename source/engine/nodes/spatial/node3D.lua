local readValue = require('../../math.managedValue').read
local Node = require('../core.baseNode')
local Math = require('../../math.math3d')
local Affine = require('../../math.affine')
local Validate = require('../../core.validate')

local Node3D = Node.define('Node3D', 'Node')

local UNIT, ZERO = { 1, 1, 1 }, { 0, 0, 0 }

function Node3D.initialize(self)
    local omitted = require('source.engine.nodes.core.classPolicy').omitted(self._class)
    if not omitted.transparency then
        self.transparency = self.transparency or 0
    end
    if not omitted.shadowGroup then
        self.shadowGroup = self.shadowGroup or (self.shadowLayers == 1 and 'SceneCamera' or 'Default')
    end
    if not omitted.position then
        self.position = self.position or { 0, 0, 0 }
    end
    if not omitted.rotation then
        self.rotation = self.rotation or { 0, 0, 0 }
    end
    self.size = self.size or { 1, 1, 1 }
    if self:isA('BillboardUI') or self:isA('Decal3D') then
        if self.scale then
            assert(
                self.scale[1] == 1 and self.scale[2] == 1 and self.scale[3] == 1,
                'World3D UI uses Size; independent scale is unsupported'
            )
        end
        self.scale = nil
        self._spatialScale = { 1, 1, 1 }
    elseif not omitted.scale then
        self.scale = self.scale or { 1, 1, 1 }
    end
end

function Node3D:getEffectiveOpacity()
    local node, alpha = self, 1
    while node do
        if node:isA('Node3D') then
            local t = node.transparency or 0
            assert(
                type(t) == 'number' and t >= 0 and t <= 1,
                'Node3D.Transparency must be within 0..1'
            )
            alpha = alpha * (1 - t)
        end
        node = node.parent
    end
    return alpha
end
-- Rendering needs both results; collect them in one ancestor traversal.
function Node3D:getVisibilityState()
    local node, alpha, visible = self, 1, true
    while node do
        visible = visible and node.visible ~= false
        if node:isA('Node3D') then
            local t = node.transparency or 0
            assert(
                type(t) == 'number' and t >= 0 and t <= 1,
                'Node3D.Transparency must be within 0..1'
            )
            alpha = alpha * (1 - t)
        end
        node = node.parent
    end
    return visible, alpha
end

function Node3D:isVisible()
    local node = self
    while node do
        if node.visible == false then
            return false
        end
        node = node.parent
    end
    return true
end

function Node3D:getWorldMatrix()
    local body = rawget(self, 'body')
    if body and self._independentBody then
        body:sync()
    end
    local p, r, s =
        readValue(self.spatialPosition or self.position or ZERO),
        readValue(self.rotation or ZERO),
        readValue(self.scale or self._spatialScale or UNIT)
    if self._spatialScale then
        assert(self.scale == nil, 'World3D UI uses Size rather than scale')
    end
    local validated = self._validatedTransform
    if
        not validated
        or validated[1] ~= p[1]
        or validated[2] ~= p[2]
        or validated[3] ~= p[3]
        or validated[4] ~= r[1]
        or validated[5] ~= r[2]
        or validated[6] ~= r[3]
        or validated[7] ~= s[1]
        or validated[8] ~= s[2]
        or validated[9] ~= s[3]
    then
        Validate.vector(p, 'Node3D.position', 3)
        Validate.vector(r, 'Node3D.rotation', 3)
        Validate.vector(s, 'Node3D.scale', 3)
        validated = validated or {}
        self._validatedTransform = validated
        validated[1], validated[2], validated[3] = p[1], p[2], p[3]
        validated[4], validated[5], validated[6] = r[1], r[2], r[3]
        validated[7], validated[8], validated[9] = s[1], s[2], s[3]
    end
    for i = 1, 3 do
        assert(s[i] > 1e-6, 'Node3D.scale must be positive and nonzero')
        if body then
            assert(
                math.abs(s[i] - body.initialScale) < 1e-6,
                'Body3D scale changes require rebuilding the body'
            )
            assert(
                self.size[i] == body.initialSize[i],
                'Body3D size changes require rebuilding the body'
            )
        end
    end
    if self:isA('Camera3D') then
        self._nodeRotation = self._nodeRotation or {}
        self._nodeRotation[1], self._nodeRotation[2], self._nodeRotation[3] = -r[1], -r[2], r[3]
        r = self._nodeRotation
    end
    self._transform = self._transform or Math.identity()
    self._localTransform = self._localTransform or Math.identity()
    self._transformValues = self._transformValues or {}
    local changed = self._transformRevision == nil
    for i = 1, 3 do
        if
            self._transformValues[i] ~= p[i]
            or self._transformValues[i + 3] ~= r[i]
            or self._transformValues[i + 6] ~= s[i]
        then
            changed = true
        end
        self._transformValues[i], self._transformValues[i + 3], self._transformValues[i + 6] =
            p[i], r[i], s[i]
    end
    local parentMatrix, parentRevision
    local spatialParent = self.parent
    while spatialParent and not spatialParent.getWorldMatrix do
        spatialParent = spatialParent.parent
    end
    if spatialParent then
        parentMatrix = spatialParent:getWorldMatrix()
        parentRevision = spatialParent._transformRevision
        if self.inheritScale == false then
            self._parentFrame = self._parentFrame or Math.identity()
            Affine.withoutScale(parentMatrix, self._parentFrame)
            parentMatrix = self._parentFrame
        end
    end
    if
        self._parentRevision ~= parentRevision
        or self._spatialParent ~= spatialParent
        or self._inheritScale ~= self.inheritScale
    then
        changed = true
    end
    if self.poseMatrix then
        self._poseValues = self._poseValues or {}
        for i = 1, 16 do
            if self._poseValues[i] ~= self.poseMatrix[i] then
                changed = true
            end
            self._poseValues[i] = self.poseMatrix[i]
        end
    end
    if self.physicsMatrix then
        self._physicsValues = self._physicsValues or {}
        for i = 1, 16 do
            if self._physicsValues[i] ~= self.physicsMatrix[i] then
                changed = true
            end
            self._physicsValues[i] = self.physicsMatrix[i]
        end
    elseif self._physicsValues then
        self._physicsValues = nil
        changed = true
    end
    if changed then
        Math.compose(p, r, s, self._localTransform)
        local localMatrix = self.physicsMatrix or self._localTransform
        if self.poseMatrix and not self.physicsMatrix then
            self._posedLocal =
                Math.multiply(self.poseMatrix, self._localTransform, self._posedLocal)
            localMatrix = self._posedLocal
        end
        if parentMatrix and (not self.physicsMatrix or self._independentBody) then
            Math.multiply(parentMatrix, localMatrix, self._transform)
        else
            for i = 1, 16 do
                self._transform[i] = localMatrix[i]
            end
        end
        self._spatialParent, self._inheritScale = spatialParent, self.inheritScale
        self._parentRevision = parentRevision
        self._transformRevision = (self._transformRevision or 0) + 1
    end
    return self._transform
end
-- Explicit visual transform: never changes Position/Rotation or the solver pose.
function Node3D:getRenderWorldMatrix()
    local exact = self:getWorldMatrix() -- validate authored changes and refresh the local transform
    local owner = self
    while
        owner
        and not (owner.body and owner.body.physics.interpolate and owner.body.type ~= 'Static')
    do
        owner = owner.parent
    end
    if not owner then
        if self._renderExactRevision ~= self._transformRevision or self._renderWasInterpolated then
            self._renderRevision = (self._renderRevision or 0) + 1
        end
        self._renderExactRevision = self._transformRevision
        self._renderWasInterpolated = false
        return exact
    end
    local wasInterpolated = self._renderWasInterpolated
    self._renderWasInterpolated = true
    local matrix
    if self.body then
        matrix = self.body:getRenderMatrix()
    elseif self.physicsMatrix then
        matrix = exact
    else
        local parent = self.parent
        while parent and not parent.getWorldMatrix do
            parent = parent.parent
        end
        -- Physics interpolation changes the ancestor pose, not the imported
        -- local pose. Dropping poseMatrix here collapses animated model scales.
        local localMatrix = self.poseMatrix and self._posedLocal or self._localTransform
        if parent then
            local pm = parent:getRenderWorldMatrix()
            if self.inheritScale == false then
                pm = Affine.withoutScale(pm, self._renderParentFrame)
                self._renderParentFrame = pm
            end
            self._renderTransform = self._renderTransform or Math.identity()
            matrix = Math.multiply(pm, localMatrix, self._renderTransform)
        else
            matrix = self._transform
        end
    end
    self._renderValues = self._renderValues or {}
    local changed = self._renderRevision == nil or not wasInterpolated
    for i = 1, 16 do
        if self._renderValues[i] ~= matrix[i] then
            changed = true
        end
        self._renderValues[i] = matrix[i]
    end
    if changed then
        self._renderRevision = (self._renderRevision or 0) + 1
    end
    return matrix
end

function Node3D:getRenderWorldPosition(out)
    out = out or {}
    local m = self:getRenderWorldMatrix()
    out[1], out[2], out[3] = m[4], m[8], m[12]
    return out
end

function Node3D:getWorldPosition(out)
    out = out or {}
    local m = self:getWorldMatrix()
    out[1], out[2], out[3] = m[4], m[8], m[12]
    return out
end

function Node3D:getWorldCFrame()
    local CFrame = require('source.engine.math.cframe')
    local m = Affine.withoutScale(self:getWorldMatrix())
    return CFrame.fromMatrix({ m[4], m[8], m[12] }, { m[1], m[5], m[9] }, { m[2], m[6], m[10] })
end

function Node3D:setCFrame(frame)
    local p, r = Affine.decompose(frame.matrix)
    if self:isA('Camera3D') then
        r[1], r[2] = -r[1], -r[2]
    end
    return self:setLocalTransform({ position = p, rotation = r })
end
require('./transformApi').install(Node3D)
return Node3D
