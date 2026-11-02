local Array = require('../../math.array')
local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local Math = require('../../math.math3d')
local Affine = require('../../math.affine')
local Validate = require('../../core.validate')
local Parenting = require('../core.parenting')
local Base = require('../core.baseNode')

local function pose(node, matrix)
    local p, r, s = Affine.decompose(matrix)
    if node:isA('Camera3D') then
        r[1], r[2] = -r[1], -r[2]
    end
    return { position = p, rotation = r, scale = s }
end

local function compatible(node, transform)
    for _, key in ipairs({ 'position', 'rotation', 'scale' }) do
        Validate.vector(transform[key], 'Transform.' .. key, 3)
    end
    for i = 1, 3 do
        if node._spatialScale then
            assert(
                math.abs(transform.scale[i] - 1) < 1e-6,
                'World3D UI uses Size; transform scale must remain one'
            )
        end
        assert(transform.scale[i] > 1e-6, 'Scale must be positive and nonzero')
        if node.body then
            assert(
                math.abs(transform.scale[i] - node.body.initialScale) < 1e-6,
                'Body3D scale changes require rebuilding the body'
            )
        end
    end
end
local TransformApi = {}

function TransformApi.install(Node3D)
    function Node3D:getLocalMatrix(out)
        self:getWorldMatrix()
        return Affine.copy(self.physicsMatrix or self._localTransform, out)
    end

    function Node3D:getLocalTransform()
        return pose(self, self:getLocalMatrix())
    end

    function Node3D:getWorldTransform()
        return pose(self, self:getWorldMatrix())
    end

    function Node3D:setLocalTransform(transform)
        assert(not self.destroyed and not self._destroying, 'Transform requires a live node')
        local target = {
            position = transform.position or self.spatialPosition or self.position,
            rotation = transform.rotation or self.rotation,
            scale = transform.scale or self.scale or self._spatialScale,
        }
        compatible(self, target)
        if self.spatialPosition then
            self.spatialPosition = { unpack(target.position) }
        else
            self.position = { unpack(target.position) }
        end
        self.rotation = { unpack(target.rotation) }
        if self._spatialScale then
            self._spatialScale = { unpack(target.scale) }
        else
            self.scale = { unpack(target.scale) }
        end
        if self.body then
            self.body:teleportLocal(self.position, self.rotation)
        end
        return self
    end

    function Node3D:setLocalMatrix(matrix)
        return self:setLocalTransform(pose(self, matrix))
    end

    function Node3D:setWorldMatrix(matrix)
        local parent = Affine.parentMatrix(self, self.parent)
        local localMatrix = matrix
        if parent and (not self.body or self._independentBody) then
            localMatrix = Math.multiply(Affine.inverse(parent), matrix)
        end
        return self:setLocalMatrix(localMatrix)
    end

    function Node3D:setWorldTransform(transform)
        local parentMatrix, parentOwner = Affine.parentMatrix(self, self.parent)
        if self:isA('Camera3D') and (not parentMatrix or parentOwner:isA('World3D')) then
            -- Preserve unrestricted yaw without Euler decomposition.
            return self:setLocalTransform(transform)
        end
        local r = { unpack(transform.rotation) }
        if self:isA('Camera3D') then
            r[1], r[2] = -r[1], -r[2]
        end
        return self:setWorldMatrix(
            Math.compose(transform.position, r, transform.scale or { 1, 1, 1 })
        )
    end

    function Node3D:setWorldCFrame(frame)
        local p, r = Affine.decompose(frame.matrix)
        local _, _, s = Affine.decompose(self:getWorldMatrix())
        return self:setWorldMatrix(Math.compose(p, r, s))
    end

    function Node3D:pointToWorldSpace(point, out)
        out = out or {}
        out[1], out[2], out[3] = Math.transform(self:getWorldMatrix(), point[1], point[2], point[3])
        return out
    end

    function Node3D:pointToLocalSpace(point, out)
        out = out or {}
        out[1], out[2], out[3] =
            Math.transform(Affine.inverse(self:getWorldMatrix()), point[1], point[2], point[3])
        return out
    end

    function Node3D:vectorToWorldSpace(vector, out)
        out = out or {}
        out[1], out[2], out[3] =
            Math.transform(self:getWorldMatrix(), vector[1], vector[2], vector[3], 0)
        return out
    end

    function Node3D:vectorToLocalSpace(vector, out)
        out = out or {}
        out[1], out[2], out[3] = Math.transform(
            Affine.inverse(self:getWorldMatrix()),
            vector[1],
            vector[2],
            vector[3],
            0
        )
        return out
    end

    function Node3D:setParent(parent, options)
        if not options or not options.keepWorldTransform then
            return Base.setParent(self, parent)
        end
        assert(
            parent == nil or (Array.is(parent) and parent._node and not parent.destroyed),
            'Parent must be a live Node'
        )
        Parenting.validate(self, parent)
        local world = Affine.copy(self:getWorldMatrix())
        local parentMatrix = Affine.parentMatrix(self, parent)
        local localMatrix = parentMatrix
                and (not self.body or self._independentBody)
                and Math.multiply(Affine.inverse(parentMatrix), world)
            or world
        local target = pose(self, localMatrix)
        compatible(self,
            target) -- Reject shear/physics incompatibility before modifying the live hierarchy.
        if self.spatialPosition then
            self.spatialPosition = target.position
        else
            self.position = target.position
        end
        self.rotation = target.rotation
        if self._spatialScale then
            self._spatialScale = target.scale
        else
            self.scale = target.scale
        end
        self._transformRevision = nil
        Base.setParent(self, parent)
        return self
    end
end

return TransformApi
