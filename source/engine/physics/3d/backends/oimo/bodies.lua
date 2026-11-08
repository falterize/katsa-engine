local O = require('./types')
local Policy = require('../../internal.bodyPolicy')
local Level = require('../../collisionLevel')
local vec, valid, types = Policy.vec, Policy.valid, Policy.types
local Bodies = {}

function Bodies.create(physics, object, settings, scale)
    local config = O.RigidBodyConfig.new()
    local kind = settings.type or 'Dynamic'
    assert(types[kind] ~= nil, 'Unknown rigid body type: ' .. tostring(kind))
    config.type = types[kind]
    config.position = vec(
        object._independentBody and object:getWorldPosition() or object.position,
        1 / physics.units
    )
    local m = object:getWorldMatrix()
    config.rotation = O.Mat3.new(
        m[1] / scale,
        m[2] / scale,
        m[3] / scale,
        m[5] / scale,
        m[6] / scale,
        m[7] / scale,
        m[9] / scale,
        m[10] / scale,
        m[11] / scale
    )
    config.linearDamping = settings.linearDamping or 0.05
    config.angularDamping = settings.angularDamping or 0.05
    config.autoSleep = settings.autoSleep ~= false
    config.sleepingVelocityThreshold = settings.sleepingVelocityThreshold or 0.2
    config.sleepingAngularVelocityThreshold = settings.sleepingAngularVelocityThreshold or 0.5
    config.sleepingTimeThreshold = settings.sleepingTimeThreshold or 1
    valid(config.linearDamping, 'Body3D.linearDamping', 0)
    valid(config.angularDamping, 'Body3D.angularDamping', 0)
    assert(
        not Level.isTrimesh(settings.collisionLevel or 'Bounding Box') or kind == 'Static',
        'Trimesh collision is supported for static bodies only'
    )
    return O.RigidBody.new(config)
end

function Bodies.createColliderCandidate()
    return O.RigidBody.new(O.RigidBodyConfig.new())
end

function Bodies.pointInverseMass(body, x, y, z)
    local raw = body.raw
    local rotation = x * (raw._invInertia00 * x + raw._invInertia01 * y + raw._invInertia02 * z)
        + y * (raw._invInertia10 * x + raw._invInertia11 * y + raw._invInertia12 * z)
        + z * (raw._invInertia20 * x + raw._invInertia21 * y + raw._invInertia22 * z)
    return 1 / body:getMass() + rotation
end

return Bodies
