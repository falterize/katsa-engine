local readValue = require('source.engine.math.managedValue').read
local PoseSpace = require('./poseSpace')
local unpack = require('source.engine.math.array').unpack
local O = require('../valueTypes')
local Math = require('source.engine.math.math3d')
local Affine = require('source.engine.math.affine')
local Policy = require('./bodyPolicy')

local vec = Policy.vec
local BodyMotion = {}

function BodyMotion.install(Physics, Body3D)
    function Body3D:applyForceAt(value, position)
        self.raw:applyForce(
            vec(value, 1 / self.physics.units),
            vec(position, 1 / self.physics.units)
        )
    end

    function Body3D:applyImpulseAt(value, position)
        self.raw:applyImpulse(
            vec(value, 1 / self.physics.units),
            vec(position, 1 / self.physics.units)
        )
    end

    function Body3D:setAngularVelocity(value)
        self.raw:setAngularVelocity(vec(value, 1))
    end

    function Body3D:applyTorque(value)
        self.raw:applyTorque(vec(value, 1 / (self.physics.units * self.physics.units)))
    end

    function Body3D:applyAngularImpulse(value)
        self.raw:applyAngularImpulse(vec(value, 1 / (self.physics.units * self.physics.units)))
    end

    function Body3D:getMass()
        return self.raw:getMass()
    end

    function Body3D:setVelocity(value)
        local u = self.physics.units
        self.physics.scratch:init(value[1] / u, value[2] / u, value[3] / u)
        self.raw:setLinearVelocity(self.physics.scratch)
    end

    function Body3D:getVelocity(out)
        out = out or {}
        self.raw:getLinearVelocityTo(self.physics.scratch)
        local v, u = self.physics.scratch, self.physics.units
        out[1], out[2], out[3] = v.x * u, v.y * u, v.z * u
        return out
    end

    function Body3D:teleport(position, rotation)
        if self.physics._stepping or self.physics._flushing or self.physics._querying then
            self.physics.pendingPoses = self.physics.pendingPoses or {}
            table.insert(self.physics.pendingPoses, {
                body = self,
                position = { unpack(position) },
                rotation = rotation and { unpack(rotation) },
            })
            return
        end
        self.raw:setPosition(vec(position, 1 / self.physics.units))
        if rotation then
            local m = Math.compose({ 0, 0, 0 }, rotation, { 1, 1, 1 })
            self.raw:setRotation(O.Mat3.new(m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11]))
        end
        self.raw:wakeUp()
        self._poseSnapshot = nil
        if self._renderPose then
            self:resetRenderPose()
        end
        self:sync()
    end

    function Body3D:applyImpulse(value)
        self.raw:applyLinearImpulse(vec(value, 1 / self.physics.units))
    end

    function Body3D:applyForce(value)
        self.raw:applyForceToCenter(vec(value, 1 / self.physics.units))
    end

    function Body3D:sync()
        if self._applyingPose then
            return
        end
        local o = self.object
        local position, authoredRotation = readValue(o.position), readValue(o.rotation)
        local authored = self._poseSnapshot
        if self.object._independentBody and authored then
            local changed = false
            for i = 1, 3 do
                if position[i] ~= authored[i] or authoredRotation[i] ~= authored[i + 3] then
                    changed = true
                end
            end
            if changed then
                self._applyingPose = true
                local ok, err =
                    pcall(self.teleportLocal, self, self.object.position, self.object.rotation)
                self._applyingPose = false
                if not ok then
                    error(err, 0)
                end
            end
        end
        local o, u = self.object, self.physics.units
        self.raw:getPositionTo(self.physics.scratch)
        local p = self.physics.scratch
        self.raw:getRotationTo(self.physics.rotation)
        local rotation = self.physics.rotation
        self._worldPhysicsMatrix = self._worldPhysicsMatrix or Math.identity()
        local m, s, size = self._worldPhysicsMatrix, readValue(o.scale), readValue(o.size)
        for i = 1, 3 do
            assert(
                math.abs(s[i] - self.initialScale) < 1e-6 and size[i] == self.initialSize[i],
                'Body3D scale or size changes require rebuilding the body'
            )
        end
        m[1], m[2], m[3], m[4] =
            rotation.e00 * s[1], rotation.e01 * s[2], rotation.e02 * s[3], p.x * u
        m[5], m[6], m[7], m[8] =
            rotation.e10 * s[1], rotation.e11 * s[2], rotation.e12 * s[3], p.y * u
        m[9], m[10], m[11], m[12] =
            rotation.e20 * s[1], rotation.e21 * s[2], rotation.e22 * s[3], p.z * u
        local inverse
        if o._independentBody then
            local parent = Affine.parentMatrix(o, o.parent)
            inverse = PoseSpace.parentInverse(self, parent)
        end
        if PoseSpace.matches(self, m, position, authoredRotation) then
            return
        end
        if o._independentBody then
            if inverse then
                self._localPhysicsMatrix = Math.multiply(inverse, m, self._localPhysicsMatrix)
                m = self._localPhysicsMatrix
                -- The next sync builds the world pose in its own buffer, never in the local result.
            end
        end
        o.physicsMatrix = m
        for i = 1, 3 do
            local value = m[i * 4]
            if position[i] ~= value then
                o.position[i] = value
            end
        end
        self.rotationMatrix = self.rotationMatrix or Math.identity()
        self.rotationAngles = self.rotationAngles or {}
        local angles = Affine.euler(Affine.rotation(m, self.rotationMatrix), self.rotationAngles)
        for i = 1, 3 do
            if authoredRotation[i] ~= angles[i] then
                o.rotation[i] = angles[i]
            end
        end
        if o._independentBody then
            self._poseSnapshot = self._poseSnapshot or {}
            for i = 1, 3 do
                self._poseSnapshot[i] = position[i]
                self._poseSnapshot[i + 3] = authoredRotation[i]
            end
        end
        PoseSpace.capture(self, self._worldPhysicsMatrix, position, authoredRotation)
    end
end

return BodyMotion
