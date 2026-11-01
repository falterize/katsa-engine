local Jobs = require('source.engine.physics.3d.backends.jolt.native.jobs')
local Library = require('source.engine.physics.3d.backends.jolt.library')
local NativeMath = require('source.engine.physics.3d.backends.jolt.nativeMath')
local O = require('source.engine.physics.3d.backends.oimo.types')

local C, ffi = Library.C, Library.ffi
local vector, cast = NativeMath.vector, NativeMath.cast

local Constraints = {}

local function spring(out, springDamper)
    if springDamper then
        out.mode = 0
        out.frequencyOrStiffness = springDamper.frequency
        out.damping = springDamper.dampingRatio
    end
end

local function limits(out, limitMotor)
    if limitMotor and limitMotor.lowerLimit <= limitMotor.upperLimit then
        out.limitsMin, out.limitsMax = limitMotor.lowerLimit, limitMotor.upperLimit
    end
end

local function normal(axis)
    local x, y, z = axis.x or axis[1], axis.y or axis[2], axis.z or axis[3]
    if math.abs(y) < 0.9 then
        local n = math.sqrt(x * x + z * z)
        return { -z / n, 0, x / n }
    end
    local n = math.sqrt(y * y + z * z)
    return { 0, z / n, -y / n }
end

function Constraints:createJoint(kind, a, b, settings)
    assert(a.raw._joltPtr and b.raw._joltPtr, 'Jolt joint endpoints must be in the world')
    local nativeKind = ({
        Spherical = 'Point',
        Revolute = 'Hinge',
        Prismatic = 'Slider',
        Ragdoll = 'SwingTwist',
    })[kind] or 'SixDOF'
    if kind == 'Spherical' and settings.springDamper and settings.springDamper.frequency > 0 then
        nativeKind = 'Distance'
    end
    local config = ffi.new('JPH_' .. nativeKind .. 'ConstraintSettings')
    C['JPH_' .. nativeKind .. 'ConstraintSettings_Init'](config)
    config.space = 0 -- LocalToBodyCOM; authored anchors are adjusted below.
    -- Jolt's LocalToBodyCOM origin differs for offset compound colliders.
    -- Convert authored body-local anchors to each body's COM-local frame.
    local function anchor(out, body, p)
        local scale = (body.initialScale or 1) / self.physics.units
        vector(out, p or { 0, 0, 0 }, scale)
        C.JPH_Shape_GetCenterOfMass(body.raw._joltShape, self.v1)
        out.x, out.y, out.z = out.x - self.v1.x, out.y - self.v1.y, out.z - self.v1.z
    end
    if nativeKind == 'SwingTwist' or nativeKind == 'SixDOF' then
        anchor(config.position1, a, settings.anchor1)
        anchor(config.position2, b, settings.anchor2)
    else
        anchor(config.point1, a, settings.anchor1)
        anchor(config.point2, b, settings.anchor2)
    end
    local x1, x2 =
        settings.localAxis1 or settings.localTwistAxis1 or { 1, 0, 0 },
        settings.localAxis2 or settings.localTwistAxis2 or { 1, 0, 0 }
    if nativeKind == 'Distance' then
        config.minDistance, config.maxDistance = 0, 0
        spring(config.limitsSpringSettings, settings.springDamper)
    end
    if nativeKind == 'Hinge' or nativeKind == 'Slider' then
        vector(config[nativeKind == 'Hinge' and 'hingeAxis1' or 'sliderAxis1'], x1)
        vector(config[nativeKind == 'Hinge' and 'hingeAxis2' or 'sliderAxis2'], x2)
        vector(config.normalAxis1, normal(x1))
        vector(config.normalAxis2, normal(x2))
        limits(config, settings.limitMotor)
        spring(config.limitsSpringSettings, settings.springDamper)
        if nativeKind == 'Hinge' then
            config.limitsMin = math.max(-math.pi, config.limitsMin)
            config.limitsMax = math.min(math.pi, config.limitsMax)
        end
        local limitMotor = settings.limitMotor
        if limitMotor then
            local force = limitMotor.motorTorque or limitMotor.motorForce or 0
            config.motorSettings.minForceLimit, config.motorSettings.maxForceLimit = -force, force
            config.motorSettings.minTorqueLimit, config.motorSettings.maxTorqueLimit = -force, force
        end
    elseif nativeKind == 'SwingTwist' then
        vector(config.twistAxis1, x1)
        vector(config.twistAxis2, x2)
        vector(config.planeAxis1, settings.localSwingAxis1 or normal(x1))
        vector(config.planeAxis2, settings.localSwingAxis2 or normal(x2))
        config.normalHalfConeAngle =
            math.max(0, math.min(math.pi, settings.maxSwingAngle1 or math.pi / 4))
        config.planeHalfConeAngle =
            math.max(0, math.min(math.pi, settings.maxSwingAngle2 or math.pi / 4))
        local limitMotor = settings.twistLimitMotor
        if limitMotor and limitMotor.lowerLimit <= limitMotor.upperLimit then
            config.twistMinAngle, config.twistMaxAngle =
                math.max(-math.pi, limitMotor.lowerLimit), math.min(math.pi, limitMotor.upperLimit)
        end
    elseif nativeKind == 'SixDOF' then
        local function axes(basis, x, y)
            if basis then
                x.x, x.y, x.z = basis.e00, basis.e10, basis.e20
                y.x, y.y, y.z = basis.e01, basis.e11, basis.e21
            else
                vector(x, x1)
                vector(y, normal(x1))
            end
        end
        axes(settings.localBasis1, config.axisX1, config.axisY1)
        if settings.localBasis2 then
            axes(settings.localBasis2, config.axisX2, config.axisY2)
        else
            vector(config.axisX2, x2)
            vector(config.axisY2, normal(x2))
        end
        for i = 0, 5 do
            config.limitMin[i], config.limitMax[i] = 0, 0
        end
        if kind == 'Generic' then
            for i = 0, 2 do
                local t = settings.translationalLimitMotors and settings.translationalLimitMotors[i]
                local r = settings.rotationalLimitMotors and settings.rotationalLimitMotors[i]
                if t then
                    config.limitMin[i], config.limitMax[i] = t.lowerLimit, t.upperLimit
                end
                if r then
                    config.limitMin[i + 3], config.limitMax[i + 3] = r.lowerLimit, r.upperLimit
                end
            end
        elseif kind == 'Cylindrical' then
            config.limitMin[0], config.limitMax[0] = 1, 0
            local limitMotor = settings.rotationalLimitMotor
            config.limitMin[3], config.limitMax[3] =
                limitMotor and limitMotor.lowerLimit or 1, limitMotor and limitMotor.upperLimit or 0
        elseif kind == 'Universal' then
            local limitMotor = settings.limitMotor1
            for i = 3, 4 do
                config.limitMin[i], config.limitMax[i] =
                    limitMotor and limitMotor.lowerLimit or 1,
                    limitMotor and limitMotor.upperLimit or 0
            end
        else
            error('Unknown Jolt constraint kind: ' .. tostring(kind))
        end
        local limitMotor = kind == 'Cylindrical' and settings.rotationalLimitMotor
            or kind == 'Universal' and settings.limitMotor1
        if limitMotor then
            for i = 3, (kind == 'Universal' and 4 or 3) do
                local force = limitMotor.motorTorque or 0
                config.motorSettings[i].minTorqueLimit, config.motorSettings[i].maxTorqueLimit =
                    -force, force
                spring(
                    config.motorSettings[i].springSettings,
                    kind == 'Universal' and settings.springDamper1
                        or settings.rotationalSpringDamper
                )
            end
        end
        -- Jolt represents free axes as [-FLT_MAX, FLT_MAX], fixed as [0,0].
        for i = 0, 5 do
            if config.limitMin[i] > config.limitMax[i] then
                config.limitMin[i], config.limitMax[i] = -3.402823466e38, 3.402823466e38
            end
        end
    end
    local ptr =
        C['JPH_' .. nativeKind .. 'Constraint_Create'](config, a.raw._joltPtr, b.raw._joltPtr)
    assert(ptr ~= nil, 'Jolt constraint creation failed: ' .. kind)
    local joint = {
        ptr = cast('Constraint', ptr),
        typed = ptr,
        kind = nativeKind,
        a = a.raw,
        b = b.raw,
        allowCollision = settings.allowCollision,
        breakForce = settings.breakForce or 0,
        breakTorque = settings.breakTorque or 0,
    }
    C.JPH_PhysicsSystem_AddConstraint(self.system, joint.ptr)
    self.joints[joint] = true
    if not settings.allowCollision then
        local ai, bi = a.raw._joltId, b.raw._joltId
        self.noCollision[ai], self.noCollision[bi] =
            self.noCollision[ai] or {}, self.noCollision[bi] or {}
        self.noCollision[ai][bi] = (self.noCollision[ai][bi] or 0) + 1
        self.noCollision[bi][ai] = (self.noCollision[bi][ai] or 0) + 1
        Jobs.exclude(self, ai, bi, true)
        C.JPH_BodyInterface_InvalidateContactCache(self.interface, ai)
        C.JPH_BodyInterface_InvalidateContactCache(self.interface, bi)
    end
    if nativeKind == 'Hinge' or nativeKind == 'Slider' then
        local limitMotor = settings.limitMotor
        if limitMotor and (limitMotor.motorTorque or limitMotor.motorForce or 0) > 0 then
            C['JPH_' .. nativeKind .. 'Constraint_SetMotorState'](ptr, 1)
            C[nativeKind == 'Hinge' and 'JPH_HingeConstraint_SetTargetAngularVelocity' or 'JPH_SliderConstraint_SetTargetVelocity'](
                ptr,
                limitMotor.motorSpeed
            )
        end
    elseif nativeKind == 'SixDOF' and (kind == 'Cylindrical' or kind == 'Universal') then
        local limitMotor = kind == 'Cylindrical' and settings.rotationalLimitMotor
            or settings.limitMotor1
        if limitMotor and limitMotor.motorTorque > 0 then
            self.v1.x, self.v1.y, self.v1.z =
                limitMotor.motorSpeed, kind == 'Universal' and limitMotor.motorSpeed or 0, 0
            C.JPH_SixDOFConstraint_SetTargetAngularVelocityCS(ptr, self.v1)
            for i = 3, (kind == 'Universal' and 4 or 3) do
                C.JPH_SixDOFConstraint_SetMotorState(ptr, i, 1)
            end
        end
    elseif
        nativeKind == 'SwingTwist'
        and settings.twistLimitMotor
        and settings.twistLimitMotor.motorTorque > 0
    then
        -- joltc does not expose SwingTwist's motor-state setters. Apply a
        -- bounded angular motor impulse while Jolt solves the cone limits.
        joint.motor = {
            axis = O.Vec3.new(x1.x or x1[1], x1.y or x1[2], x1.z or x1[3]),
            speed = settings.twistLimitMotor.motorSpeed,
            torque = settings.twistLimitMotor.motorTorque,
        }
    end
    return joint
end

function Constraints:stepMotors(dt)
    for joint in pairs(self.joints) do
        local motor = joint.motor
        if motor and joint.ptr then
            local a, b = joint.a, joint.b
            a:getRotationTo(self.oRotation)
            local m, v = self.oRotation, motor.axis
            local x, y, z =
                m.e00 * v.x + m.e01 * v.y + m.e02 * v.z,
                m.e10 * v.x + m.e11 * v.y + m.e12 * v.z,
                m.e20 * v.x + m.e21 * v.y + m.e22 * v.z
            C.JPH_Body_GetAngularVelocity(a._joltPtr, self.v1)
            C.JPH_Body_GetAngularVelocity(b._joltPtr, self.v2)
            local speed = (self.v2.x - self.v1.x) * x
                + (self.v2.y - self.v1.y) * y
                + (self.v2.z - self.v1.z) * z
            local function inverse(raw)
                if raw._type ~= 0 then
                    return 0
                end
                C.JPH_Body_GetInverseInertia(raw._joltPtr, self.matrix)
                local c = self.matrix.column
                return x * (c[0].x * x + c[1].x * y + c[2].x * z)
                    + y * (c[0].y * x + c[1].y * y + c[2].y * z)
                    + z * (c[0].z * x + c[1].z * y + c[2].z * z)
            end
            local inv = inverse(a) + inverse(b)
            if inv > 0 then
                local impulse = math.max(
                    -motor.torque * dt,
                    math.min(motor.torque * dt, (motor.speed - speed) / inv)
                )
                if a._type == 0 then
                    self.v1.x, self.v1.y, self.v1.z = -x * impulse, -y * impulse, -z * impulse
                    C.JPH_Body_AddAngularImpulse(a._joltPtr, self.v1)
                end
                if b._type == 0 then
                    self.v1.x, self.v1.y, self.v1.z = x * impulse, y * impulse, z * impulse
                    C.JPH_Body_AddAngularImpulse(b._joltPtr, self.v1)
                end
            end
        end
    end
end

function Constraints:checkBreaks(dt)
    for joint in pairs(self.joints) do
        if joint.ptr and (joint.breakForce > 0 or joint.breakTorque > 0) then
            local force, torque = 0, 0
            local kind, ptr = joint.kind, joint.typed
            if joint.breakForce > 0 then
                if kind == 'Distance' then
                    local v = C.JPH_DistanceConstraint_GetTotalLambdaPosition(ptr)
                    force = v * v
                elseif kind == 'Slider' then
                    C.JPH_SliderConstraint_GetTotalLambdaPosition(ptr, self.lambda2)
                    local v = C.JPH_SliderConstraint_GetTotalLambdaPositionLimits(ptr)
                    force = self.lambda2[0] ^ 2 + self.lambda2[1] ^ 2 + v * v
                else
                    C['JPH_' .. kind .. 'Constraint_GetTotalLambdaPosition'](ptr, self.v1)
                    force = self.v1.x ^ 2 + self.v1.y ^ 2 + self.v1.z ^ 2
                end
            end
            if joint.breakTorque > 0 then
                if kind == 'Hinge' then
                    C.JPH_HingeConstraint_GetTotalLambdaRotation(ptr, self.lambda2)
                    local v = C.JPH_HingeConstraint_GetTotalLambdaRotationLimits(ptr)
                        + C.JPH_HingeConstraint_GetTotalLambdaMotor(ptr)
                    torque = self.lambda2[0] ^ 2 + self.lambda2[1] ^ 2 + v * v
                elseif kind == 'SwingTwist' then
                    torque = C.JPH_SwingTwistConstraint_GetTotalLambdaTwist(ptr) ^ 2
                        + C.JPH_SwingTwistConstraint_GetTotalLambdaSwingY(ptr) ^ 2
                        + C.JPH_SwingTwistConstraint_GetTotalLambdaSwingZ(ptr) ^ 2
                elseif kind == 'SixDOF' or kind == 'Slider' then
                    C['JPH_' .. kind .. 'Constraint_GetTotalLambdaRotation'](ptr, self.v1)
                    torque = self.v1.x ^ 2 + self.v1.y ^ 2 + self.v1.z ^ 2
                end
            end
            if
                joint.breakForce > 0 and force > (joint.breakForce * dt) ^ 2
                or joint.breakTorque > 0 and torque > (joint.breakTorque * dt) ^ 2
            then
                local owner = joint.ownerConstraint
                self:removeJoint(joint)
                if owner and not owner.destroyed then
                    owner.enabled = false
                    owner.status = 'Broken'
                    owner:emit('Broken', owner)
                end
            end
        end
    end
end

function Constraints:removeJoint(joint)
    if not joint.ptr then
        return
    end
    C.JPH_PhysicsSystem_RemoveConstraint(self.system, joint.ptr)
    C.JPH_Constraint_Destroy(joint.ptr)
    joint.ptr, joint.typed = nil, nil
    self.joints[joint] = nil
    if not joint.allowCollision then
        local ai, bi = joint.a._joltId, joint.b._joltId
        if ai and bi then
            local n = (self.noCollision[ai] and self.noCollision[ai][bi] or 1) - 1
            self.noCollision[ai][bi], self.noCollision[bi][ai] =
                n > 0 and n or nil, n > 0 and n or nil
            Jobs.exclude(self, ai, bi, n > 0)
            C.JPH_BodyInterface_InvalidateContactCache(self.interface, ai)
            C.JPH_BodyInterface_InvalidateContactCache(self.interface, bi)
        end
    end
end

return Constraints
