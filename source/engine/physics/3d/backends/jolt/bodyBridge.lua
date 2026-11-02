local Library = require('./library')
local NativeMath = require('./nativeMath')
local O = require('../oimo.types')
local State = require('./bodyState')

local C = Library.C

local vector, quaternion, motion = NativeMath.vector, NativeMath.quaternion, NativeMath.motion

local BodyBridge = {}

function BodyBridge:wrapBody(body)
    local raw, original = body.raw, {}
    raw._joltOwner, raw._nativeOriginal = body, original

    local function override(name, fn)
        original[name] = raw[name]
        raw[name] = fn
    end
    local world = self
    override('getPositionTo', function(raw, out)
        if not raw._joltPtr then
            return original.getPositionTo(raw, out)
        end
        local state = State.read(world, raw)
        if state then
            local position = state.position
            out:init(position.x, position.y, position.z)
            return
        end
        C.JPH_Body_GetPosition(raw._joltPtr, world.v1)
        out:init(world.v1.x, world.v1.y, world.v1.z)
    end)
    override('getPosition', function(raw)
        local out = O.Vec3.new()
        raw:getPositionTo(out)
        return out
    end)
    override('getOrientationTo', function(raw, out)
        if not raw._joltPtr then
            return original.getOrientationTo(raw, out)
        end
        local state = State.read(world, raw)
        if state then
            local rotation = state.rotation
            out:init(rotation.x, rotation.y, rotation.z, rotation.w)
            return
        end
        C.JPH_Body_GetRotation(raw._joltPtr, world.q)
        out:init(world.q.x, world.q.y, world.q.z, world.q.w)
    end)
    override('getOrientation', function(raw)
        local out = O.Quat.new()
        raw:getOrientationTo(out)
        return out
    end)
    override('getRotationTo', function(raw, out)
        if not raw._joltPtr then
            return original.getRotationTo(raw, out)
        end
        raw:getOrientationTo(world.oQuat)
        out:fromQuat(world.oQuat)
    end)
    for _, prefix in ipairs({ 'Linear', 'Angular' }) do
        local get, set = 'get' .. prefix .. 'VelocityTo', 'set' .. prefix .. 'Velocity'
        local read, write =
            C['JPH_Body_Get' .. prefix .. 'Velocity'], C['JPH_Body_Set' .. prefix .. 'Velocity']
        override(get, function(raw, out)
            if not raw._joltPtr then
                return original[get](raw, out)
            end
            local state = State.read(world, raw)
            if state then
                local velocity = prefix == 'Linear' and state.linear or state.angular
                out:init(velocity.x, velocity.y, velocity.z)
                return
            end
            read(raw._joltPtr, world.v1)
            out:init(world.v1.x, world.v1.y, world.v1.z)
        end)
        override('get' .. prefix .. 'Velocity', function(raw)
            local out = O.Vec3.new()
            raw[get](raw, out)
            return out
        end)
        override(set, function(raw, v)
            State.invalidate(raw)
            original[set](raw, v)
            if raw._joltPtr and raw._type ~= 1 then
                write(raw._joltPtr, vector(world.v1, v))
            end
        end)
    end
    override('setPosition', function(raw, v)
        State.invalidate(raw)
        raw._joltPoseCache = nil
        original.setPosition(raw, v)
        if raw._joltPtr then
            C.JPH_BodyInterface_SetPosition(world.interface, raw._joltId, vector(world.v1, v), 0)
        end
    end)
    override('setRotation', function(raw, v)
        State.invalidate(raw)
        raw._joltPoseCache = nil
        original.setRotation(raw, v)
        if raw._joltPtr then
            C.JPH_BodyInterface_SetRotation(
                world.interface,
                raw._joltId,
                quaternion(world.q, v, world.oQuat),
                0
            )
        end
    end)
    override('setType', function(raw, v)
        State.invalidate(raw)
        original.setType(raw, v)
        if raw._joltPtr then
            C.JPH_BodyInterface_SetMotionType(world.interface, raw._joltId, motion[v], 0)
        end
    end)
    override('setGravityScale', function(raw, v)
        original.setGravityScale(raw, v)
        if raw._joltPtr then
            C.JPH_BodyInterface_SetGravityFactor(world.interface, raw._joltId, v)
        end
    end)
    override('setAutoSleep', function(raw, v)
        original.setAutoSleep(raw, v)
        if raw._joltPtr then
            C.JPH_Body_SetAllowSleeping(raw._joltPtr, v)
        end
    end)
    override('setRotationFactor', function(raw, v)
        assert(
            (v.x == 0 or v.x == 1) and (v.y == 0 or v.y == 1) and (v.z == 0 or v.z == 1),
            'Jolt rotationFactor supports axis locks (0 or 1)'
        )
        original.setRotationFactor(raw, v)
        raw._joltDofs = 7 + v.x * 8 + v.y * 16 + v.z * 32
        if raw._joltPtr and raw._type ~= 1 then
            C.JPH_Shape_GetMassProperties(raw._joltShape, world.mass)
            C.JPH_MotionProperties_SetMassProperties(
                C.JPH_Body_GetMotionProperties(raw._joltPtr),
                raw._joltDofs,
                world.mass
            )
        end
    end)
    for _, kind in ipairs({ 'Linear', 'Angular' }) do
        local name = 'set' .. kind .. 'Damping'
        local setter = C['JPH_MotionProperties_Set' .. kind .. 'Damping']
        override(name, function(raw, v)
            original[name](raw, v)
            if raw._joltPtr and raw._type ~= 1 then
                setter(C.JPH_Body_GetMotionProperties(raw._joltPtr), v)
            end
        end)
    end
    override('getMass', function(raw)
        if not raw._joltPtr then
            return original.getMass(raw)
        end
        if raw._type ~= 0 then
            return original.getMass(raw)
        end
        return 1
            / C.JPH_MotionProperties_GetInverseMassUnchecked(
                C.JPH_Body_GetMotionProperties(raw._joltPtr)
            )
    end)
    override('setMassData', function(raw, v)
        original.setMassData(raw, v)
        if raw._joltPtr and raw._type == 0 then
            C.JPH_MotionProperties_ScaleToMass(C.JPH_Body_GetMotionProperties(raw._joltPtr), v.mass)
        end
    end)
    override('wakeUp', function(raw)
        original.wakeUp(raw)
        if raw._joltPtr and raw._type ~= 1 and not raw._joltPulling then
            C.JPH_BodyInterface_ActivateBody(world.interface, raw._joltId)
        end
    end)
    override('sleep', function(raw)
        State.invalidate(raw)
        original.sleep(raw)
        if raw._joltPtr and raw._type ~= 1 then
            C.JPH_BodyInterface_DeactivateBody(world.interface, raw._joltId)
        end
    end)
    override('isSleeping', function(raw)
        if not raw._joltPtr then
            return original.isSleeping(raw)
        end
        return not C.JPH_Body_IsActive(raw._joltPtr)
    end)
    local actions = {
        applyLinearImpulse = 'AddImpulse',
        applyAngularImpulse = 'AddAngularImpulse',
        applyForceToCenter = 'AddForce',
        applyTorque = 'AddTorque',
    }
    for name, suffix in pairs(actions) do
        local call = C['JPH_Body_' .. suffix]
        override(name, function(raw, v)
            if not raw._joltPtr then
                return original[name](raw, v)
            end
            if raw._type == 0 then
                State.invalidate(raw)
                call(raw._joltPtr, vector(world.v1, v))
                raw:wakeUp()
            end
        end)
    end
    for name, suffix in pairs({
        applyForce = 'AddForceAtPosition',
        applyImpulse = 'AddImpulseAtPosition',
    }) do
        local call = C['JPH_Body_' .. suffix]
        override(name, function(raw, v, p)
            if not raw._joltPtr then
                return original[name](raw, v, p)
            end
            if raw._type == 0 then
                State.invalidate(raw)
                call(raw._joltPtr, vector(world.v1, v), vector(world.v2, p))
                raw:wakeUp()
            end
        end)
    end
end

return BodyBridge
