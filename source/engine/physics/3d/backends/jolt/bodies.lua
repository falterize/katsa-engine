local Jobs = require('source.engine.physics.3d.backends.jolt.native.jobs')
local State = require('source.engine.physics.3d.backends.jolt.bodyState')
local Library = require('source.engine.physics.3d.backends.jolt.library')
local NativeMath = require('source.engine.physics.3d.backends.jolt.nativeMath')

local C = Library.C

local vector, quaternion, motion = NativeMath.vector, NativeMath.quaternion, NativeMath.motion

local Bodies = {}

function Bodies:restoreMass(body)
    local raw = body.raw
    if body.settings.mass and raw._joltPtr and raw._type == 0 then
        C.JPH_MotionProperties_ScaleToMass(
            C.JPH_Body_GetMotionProperties(raw._joltPtr),
            body.settings.mass
        )
    end
end

function Bodies:addRigidBody(raw)
    local body = raw._joltOwner
    local shape = self:makeShape(body)
    raw._joltShape = shape
    raw._nativeOriginal.getPositionTo(raw, self.oPosition)
    raw._nativeOriginal.getRotationTo(raw, self.oRotation)
    local config = C.JPH_BodyCreationSettings_Create3(
        shape,
        vector(self.v1, self.oPosition),
        quaternion(self.q, self.oRotation, self.oQuat),
        motion[raw._type],
        0
    )
    C.JPH_BodyCreationSettings_SetAllowDynamicOrKinematic(config, true)
    C.JPH_BodyCreationSettings_SetCollideKinematicVsNonDynamic(config, true)
    C.JPH_BodyCreationSettings_SetAllowedDOFs(config, raw._joltDofs or 63)
    C.JPH_BodyCreationSettings_SetLinearDamping(config, body.settings.linearDamping or 0.05)
    C.JPH_BodyCreationSettings_SetAngularDamping(config, body.settings.angularDamping or 0.05)
    C.JPH_BodyCreationSettings_SetAllowSleeping(config, body.settings.autoSleep ~= false)
    C.JPH_BodyCreationSettings_SetGravityFactor(config, body.settings.gravityScale or 1)
    C.JPH_BodyCreationSettings_SetFriction(config, body.shapes[1].raw:getFriction())
    C.JPH_BodyCreationSettings_SetRestitution(config, body.shapes[1].raw:getRestitution())
    C.JPH_BodyCreationSettings_SetMotionQuality(config, body.settings.ccd == true and 1 or 0)
    raw._nativeOriginal.getLinearVelocityTo(raw, self.oPosition)
    C.JPH_BodyCreationSettings_SetLinearVelocity(config, vector(self.v1, self.oPosition))
    raw._nativeOriginal.getAngularVelocityTo(raw, self.oPosition)
    C.JPH_BodyCreationSettings_SetAngularVelocity(config, vector(self.v1, self.oPosition))
    local ptr = C.JPH_BodyInterface_CreateBody(self.interface, config)
    C.JPH_BodyCreationSettings_Destroy(config)
    if ptr == nil then
        C.JPH_Shape_Destroy(shape)
        error('Jolt body capacity exhausted')
    end
    raw._joltPtr, raw._joltId = ptr, tonumber(C.JPH_Body_GetID(ptr))
    State.invalidate(raw)
    self.byId[raw._joltId], self.bodies[raw] = raw, true
    C.JPH_BodyInterface_AddBody(self.interface, raw._joltId, raw._type == 1 and 1 or 0)
    self.shadow:addRigidBody(raw)
    self:refreshFilters(body)
    self:restoreMass(body)
    Jobs.syncBody(self, raw)
end

function Bodies:removeRigidBody(raw)
    if not raw._joltPtr then
        return
    end
    self:refreshMirror(raw)
    for joint in pairs(self.joints) do
        if joint.a == raw or joint.b == raw then
            self:removeJoint(joint)
        end
    end
    C.JPH_BodyInterface_RemoveBody(self.interface, raw._joltId)
    Jobs.collect(self)
    self:dispatchEvents()
    C.JPH_BodyInterface_DestroyBody(self.interface, raw._joltId)
    if self.nativeContacts then
        Jobs.C.KP_RemoveBody(self.nativeContacts, raw._joltId)
    end
    C.JPH_Shape_Destroy(raw._joltShape)
    self.shadow:removeRigidBody(raw)
    self.byId[raw._joltId], self.bodies[raw] = nil, nil
    raw._joltPtr, raw._joltId, raw._joltShape = nil, nil, nil
end

function Bodies:refreshMirror(raw)
    if not raw._joltPtr or raw._joltPulling or raw._joltMirrorEpoch == self.poseEpoch then
        return
    end
    self:pull(raw)
    raw._joltMirrorEpoch = self.poseEpoch
end

function Bodies:pull(raw)
    raw._joltPulling = true
    local position, rotation, linear, angular
    if Jobs.C then
        local state = State.read(self, raw)
        position, rotation, linear, angular =
            state.position, state.rotation, state.linear, state.angular
    else
        C.JPH_Body_GetPosition(raw._joltPtr, self.v1)
        position = self.v1
        C.JPH_Body_GetRotation(raw._joltPtr, self.q)
        rotation = self.q
    end
    local cache = raw._joltPoseCache
    if not cache then
        cache = {}
        raw._joltPoseCache = cache
    end
    -- Preserve exact values; avoid rebuilding mirror transforms when only velocity changes.
    if cache[1] ~= position.x or cache[2] ~= position.y or cache[3] ~= position.z then
        self.oPosition:init(position.x, position.y, position.z)
        raw._nativeOriginal.setPosition(raw, self.oPosition)
        cache[1], cache[2], cache[3] = position.x, position.y, position.z
    end
    if
        cache[4] ~= rotation.x
        or cache[5] ~= rotation.y
        or cache[6] ~= rotation.z
        or cache[7] ~= rotation.w
    then
        self.oQuat:init(rotation.x, rotation.y, rotation.z, rotation.w)
        self.oRotation:fromQuat(self.oQuat)
        raw._nativeOriginal.setRotation(raw, self.oRotation)
        cache[4], cache[5], cache[6], cache[7] = rotation.x, rotation.y, rotation.z, rotation.w
    end
    if not linear then
        C.JPH_Body_GetLinearVelocity(raw._joltPtr, self.v1)
        linear = self.v1
    end
    self.oPosition:init(linear.x, linear.y, linear.z)
    raw._nativeOriginal.setLinearVelocity(raw, self.oPosition)
    if not angular then
        C.JPH_Body_GetAngularVelocity(raw._joltPtr, self.v1)
        angular = self.v1
    end
    self.oPosition:init(angular.x, angular.y, angular.z)
    raw._nativeOriginal.setAngularVelocity(raw, self.oPosition)
    raw._joltPulling = false
end

function Bodies:pointInverseMass(body, x, y, z)
    C.JPH_Body_GetInverseInertia(body.raw._joltPtr, self.matrix)
    local m = self.matrix.column
    local a, b, c = m[0], m[1], m[2]
    return 1 / body:getMass()
        + x * (a.x * x + b.x * y + c.x * z)
        + y * (a.y * x + b.y * y + c.y * z)
        + z * (a.z * x + b.z * y + c.z * z)
end

return Bodies
