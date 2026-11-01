-- Bodies: transforms, velocities, forces, mass and body-owned object bookkeeping.

local ffi = require('ffi')
local Binding = require('source.katsa.physics.binding')
local Scale = require('source.katsa.physics.scale')
local Registry = require('source.katsa.physics.registry')
local Object = require('source.katsa.physics.object')
local Contact = require('source.katsa.physics.contact')
local B = Binding.lib
local up = Scale.up
local down = Scale.down
local pair = Binding.pair
local quad = Binding.quad
local alive = Object.alive

local M = {}
local Body = Object.class('Body')
local typeCodes = { static = 0, dynamic = 1, kinematic = 2 }
local typeNames = { [0] = 'static', 'dynamic', 'kinematic' }

function M.newBody(world, x, y, kind)
    alive(world, 'World')
    kind = kind or 'static'
    assert(typeCodes[kind], 'Invalid body type: ' .. tostring(kind))
    local handle = B().kb2_body_new(world._h, typeCodes[kind], down(x or 0), down(y or 0), 0)
    local self = setmetatable({ _h = handle, _world = world, _fixtures = {}, _joints = {} }, Body)
    self._id = Registry.register(self)
    B().kb2_body_set_userid(handle, self._id)
    world._bodies[self] = true
    return self
end

function Body:getPosition()
    alive(self, 'Body')
    B().kb2_body_get_position(self._h, pair)
    return up(pair[0]), up(pair[1])
end

function Body:getX()
    alive(self, 'Body')
    B().kb2_body_get_position(self._h, pair)
    return up(pair[0])
end

function Body:getY()
    alive(self, 'Body')
    B().kb2_body_get_position(self._h, pair)
    return up(pair[1])
end

function Body:getAngle()
    alive(self, 'Body')
    return B().kb2_body_get_angle(self._h)
end

function Body:getTransform()
    local x, y = self:getPosition()
    return x, y, self:getAngle()
end

function Body:setPosition(x, y)
    alive(self, 'Body')
    B().kb2_body_set_transform(self._h, down(x), down(y), B().kb2_body_get_angle(self._h))
end

function Body:setX(x)
    self:setPosition(x, self:getY())
end

function Body:setY(y)
    self:setPosition(self:getX(), y)
end

function Body:setAngle(a)
    alive(self, 'Body')
    B().kb2_body_get_position(self._h, pair)
    B().kb2_body_set_transform(self._h, pair[0], pair[1], a)
end

function Body:setTransform(x, y, a)
    alive(self, 'Body')
    B().kb2_body_set_transform(self._h, down(x), down(y), a or self:getAngle())
end

function Body:getLinearVelocity()
    alive(self, 'Body')
    B().kb2_body_get_linear_velocity(self._h, pair)
    return up(pair[0]), up(pair[1])
end

function Body:setLinearVelocity(x, y)
    alive(self, 'Body')
    B().kb2_body_set_linear_velocity(self._h, down(x), down(y))
end

function Body:getAngularVelocity()
    alive(self, 'Body')
    return B().kb2_body_get_angular_velocity(self._h)
end

function Body:setAngularVelocity(v)
    alive(self, 'Body')
    B().kb2_body_set_angular_velocity(self._h, v)
end

function Body:applyForce(fx, fy, px, py)
    alive(self, 'Body')
    local point = px ~= nil
    B().kb2_body_apply_force(self._h, down(fx), down(fy), down(px or 0), down(py or 0),
        point and 1 or 0)
end

function Body:applyLinearImpulse(ix, iy, px, py)
    alive(self, 'Body')
    local point = px ~= nil
    B().kb2_body_apply_impulse(self._h, down(ix), down(iy), down(px or 0), down(py or 0),
        point and 1 or 0)
end

function Body:applyTorque(t)
    alive(self, 'Body')
    B().kb2_body_apply_torque(self._h, down(down(t)))
end

function Body:applyAngularImpulse(i)
    alive(self, 'Body')
    B().kb2_body_apply_angular_impulse(self._h, down(down(i)))
end

function Body:getMass()
    alive(self, 'Body')
    return B().kb2_body_get_mass(self._h)
end

function Body:getInertia()
    alive(self, 'Body')
    return up(up(B().kb2_body_get_inertia(self._h)))
end

function Body:getMassData()
    alive(self, 'Body')
    B().kb2_body_get_mass_data(self._h, quad)
    return up(quad[0]), up(quad[1]), quad[2], up(up(quad[3]))
end

function Body:setMassData(x, y, mass, inertia)
    alive(self, 'Body')
    B().kb2_body_set_mass_data(self._h, down(x), down(y), mass, down(down(inertia)))
end

function Body:setMass(mass)
    local x, y, _, inertia = self:getMassData()
    self:setMassData(x, y, mass, inertia)
end

function Body:setInertia(inertia)
    local x, y, mass = self:getMassData()
    self:setMassData(x, y, mass, inertia)
end

function Body:resetMassData()
    alive(self, 'Body')
    B().kb2_body_reset_mass(self._h)
end

function Body:getWorldCenter()
    alive(self, 'Body')
    B().kb2_body_get_world_center(self._h, pair)
    return up(pair[0]), up(pair[1])
end

function Body:getLocalCenter()
    alive(self, 'Body')
    B().kb2_body_get_local_center(self._h, pair)
    return up(pair[0]), up(pair[1])
end

function Body:getWorldPoint(x, y)
    alive(self, 'Body')
    B().kb2_body_world_point(self._h, down(x), down(y), pair)
    return up(pair[0]), up(pair[1])
end

function Body:getWorldVector(x, y)
    alive(self, 'Body')
    B().kb2_body_world_vector(self._h, down(x), down(y), pair)
    return up(pair[0]), up(pair[1])
end

function Body:getLocalPoint(x, y)
    alive(self, 'Body')
    B().kb2_body_local_point(self._h, down(x), down(y), pair)
    return up(pair[0]), up(pair[1])
end

function Body:getLocalVector(x, y)
    alive(self, 'Body')
    B().kb2_body_local_vector(self._h, down(x), down(y), pair)
    return up(pair[0]), up(pair[1])
end

function Body:getWorldPoints(...)
    local out, args = {}, { ... }
    for i = 1, #args - 1, 2 do
        local x, y = self:getWorldPoint(args[i], args[i + 1])
        out[#out + 1], out[#out + 2] = x, y
    end
    return unpack(out)
end

function Body:getLocalPoints(...)
    local out, args = {}, { ... }
    for i = 1, #args - 1, 2 do
        local x, y = self:getLocalPoint(args[i], args[i + 1])
        out[#out + 1], out[#out + 2] = x, y
    end
    return unpack(out)
end

function Body:getLinearVelocityFromWorldPoint(x, y)
    B().kb2_body_velocity_at(self._h, down(x), down(y), pair, 0)
    return up(pair[0]), up(pair[1])
end

function Body:getLinearVelocityFromLocalPoint(x, y)
    B().kb2_body_velocity_at(self._h, down(x), down(y), pair, 1)
    return up(pair[0]), up(pair[1])
end

function Body:getLinearDamping()
    return B().kb2_body_get_linear_damping(self._h)
end

function Body:setLinearDamping(v)
    B().kb2_body_set_linear_damping(self._h, v)
end

function Body:getAngularDamping()
    return B().kb2_body_get_angular_damping(self._h)
end

function Body:setAngularDamping(v)
    B().kb2_body_set_angular_damping(self._h, v)
end

function Body:getGravityScale()
    return B().kb2_body_get_gravity_scale(self._h)
end

function Body:setGravityScale(v)
    B().kb2_body_set_gravity_scale(self._h, v)
end

function Body:getType()
    alive(self, 'Body')
    return typeNames[B().kb2_body_get_type(self._h)]
end

function Body:setType(kind)
    alive(self, 'Body') assert(typeCodes[kind], 'Invalid body type: ' .. tostring(kind))
    B().kb2_body_set_type(self._h, typeCodes[kind])
end
local flags = { bullet = 0, fixedRotation = 1, active = 2, awake = 3, sleepingAllowed = 4 }
function Body:isBullet()
    return B().kb2_body_get_flag(self._h, 0) ~= 0
end

function Body:setBullet(v)
    B().kb2_body_set_flag(self._h, 0, v and 1 or 0)
end

function Body:isFixedRotation()
    return B().kb2_body_get_flag(self._h, 1) ~= 0
end

function Body:setFixedRotation(v)
    B().kb2_body_set_flag(self._h, 1, v and 1 or 0)
end

function Body:isActive()
    alive(self, 'Body')
    return B().kb2_body_get_flag(self._h, 2) ~= 0
end

function Body:setActive(v)
    alive(self, 'Body')
    B().kb2_body_set_flag(self._h, 2, v and 1 or 0)
end

function Body:isAwake()
    alive(self, 'Body')
    return B().kb2_body_get_flag(self._h, 3) ~= 0
end

function Body:setAwake(v)
    alive(self, 'Body')
    B().kb2_body_set_flag(self._h, 3, v and 1 or 0)
end

function Body:isSleepingAllowed()
    return B().kb2_body_get_flag(self._h, 4) ~= 0
end

function Body:setSleepingAllowed(v)
    B().kb2_body_set_flag(self._h, 4, v and 1 or 0)
end

function Body:isTouching(other)
    for _, contact in ipairs(self:getContacts()) do
        local a, b = contact:getFixtures()
        if (a:getBody() == other or b:getBody() == other) and contact:isTouching() then
            return true
        end
    end
    return false
end

function Body:getWorld()
    return self._world
end

function Body:setUserData(data)
    self._userdata = data
end

function Body:getUserData()
    return self._userdata
end

function Body:getFixtures()
    return Object.sortedKeys(self._fixtures)
end

function Body:getFixtureCount()
    return Object.count(self._fixtures)
end

function Body:getJoints()
    return Object.sortedKeys(self._joints)
end

function Body:getContacts()
    alive(self, 'Body')
    local handles = ffi.new('void*[64]')
    local n = B().kb2_body_contacts(self._h, handles, 64)
    local out = {}
    for i = 0, n - 1 do
        out[#out + 1] = Contact.wrap(handles[i])
    end
    return out
end

function Body:isDestroyed()
    return self._destroyed == true
end

function Body:destroy()
    if self._destroyed then
        return false
    end
    assert(not self._world:isLocked(), 'Cannot destroy a body while the world is locked')
    for joint in pairs(self._joints) do
        joint._destroyed = true
        Registry.unregister(joint._id)
        for _, other in ipairs({ joint._a, joint._b }) do
            if other ~= self and other then
                other._joints[joint] = nil
            end
        end
        self._world._joints[joint] = nil
    end
    self._joints = {}
    -- Native destruction fires end-contact callbacks, so fixtures stay registered until it is done.
    B().kb2_body_destroy(self._world._h, self._h)
    for fixture in pairs(self._fixtures) do
        fixture._destroyed = true
        Registry.unregister(fixture._id)
    end
    self._fixtures = {}
    self._destroyed = true
    self._world._bodies[self] = nil
    Registry.unregister(self._id)
    return true
end

M.class = Body

return M
