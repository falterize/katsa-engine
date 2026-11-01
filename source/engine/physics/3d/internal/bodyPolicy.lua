local O = require('source.engine.physics.3d.valueTypes')

local observedProperties = {
    'mass',
    'density',
    'friction',
    'restitution',
    'linearDamping',
    'angularDamping',
    'gravityScale',
    'autoSleep',
    'collisionGroup',
    'canCollide',
    'canQuery',
    'type',
}
local types = { Dynamic = 0, Static = 1, Kinematic = 2 }

local function vec(v, scale)
    return O.Vec3.new(v[1] * scale, v[2] * scale, v[3] * scale)
end

local function valid(value, name, minimum)
    assert(
        type(value) == 'number' and value == value and value < math.huge and value >= minimum,
        name .. ' is invalid'
    )
end
return { observedProperties = observedProperties, types = types, vec = vec, valid = valid }
