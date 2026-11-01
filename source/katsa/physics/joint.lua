-- Joints: constructors, anchors, reactions and teardown.

local Binding = require('source.katsa.physics.binding')
local Scale = require('source.katsa.physics.scale')
local Registry = require('source.katsa.physics.registry')
local Object = require('source.katsa.physics.object')
local B, up, down, quad, six = Binding.lib, Scale.up, Scale.down, Binding.quad, Binding.six

local M = {}
local Joint = Object.class('Joint')
require('source.katsa.physics.jointProperties')(Joint)

local jointTypes = {
    'revolute', 'prismatic', 'distance', 'pulley', 'mouse', 'gear',
    'wheel', 'weld', 'friction', 'rope', 'motor',
}

local function newJoint(world, handle, a, b)
    local self = setmetatable({ _h = handle, _world = world, _a = a, _b = b }, Joint)
    self._id = Registry.register(self)
    B().kb2_joint_set_userid(handle, self._id)
    world._joints[self] = true
    a._joints[self] = true
    if b then b._joints[self] = true end
    return self
end

local function flag(value)
    return value and 1 or 0
end

local function create(kind, b1, b2, ...)
    local world = b1._world
    return newJoint(world, B()['kb2_joint_' .. kind](world._h, b1._h, b2._h, ...), b1, b2)
end

local function referenceAngle(b1, b2, reference)
    return reference or (b2:getAngle() - b1:getAngle())
end

-- Constructors accept one shared anchor (x, y) or two anchors (x1, y1, x2, y2); with a single
-- anchor the trailing arguments shift left, which `shared` detects by the type of the fourth slot.
local function shared(x2)
    return type(x2) ~= 'number'
end

function M.newRevoluteJoint(b1, b2, x1, y1, x2, y2, collide, reference)
    if shared(x2) then
        collide, reference = x2, y2
        x2, y2 = x1, y1
    end
    local angle = referenceAngle(b1, b2, reference)
    return create('revolute', b1, b2, down(x1), down(y1), down(x2), down(y2), flag(collide), angle)
end

function M.newPrismaticJoint(b1, b2, x1, y1, x2, y2, ax, ay, collide, reference)
    if type(ay) ~= 'number' then
        collide, reference = ay, collide
        ax, ay = x2, y2
        x2, y2 = x1, y1
    end
    local angle = referenceAngle(b1, b2, reference)
    local a1, a2 = { down(x1), down(y1) }, { down(x2), down(y2) }
    return create('prismatic', b1, b2, a1[1], a1[2], a2[1], a2[2], ax, ay, flag(collide), angle)
end

function M.newWeldJoint(b1, b2, x1, y1, x2, y2, collide, reference)
    if shared(x2) then
        collide, reference = x2, y2
        x2, y2 = x1, y1
    end
    local angle = referenceAngle(b1, b2, reference)
    return create('weld', b1, b2, down(x1), down(y1), down(x2), down(y2), flag(collide), angle)
end

function M.newRopeJoint(b1, b2, x1, y1, x2, y2, maxLength, collide)
    local length = down(maxLength)
    return create('rope', b1, b2, down(x1), down(y1), down(x2), down(y2), length, flag(collide))
end

function M.newDistanceJoint(b1, b2, x1, y1, x2, y2, collide)
    return create('distance', b1, b2, down(x1), down(y1), down(x2), down(y2), flag(collide))
end

function M.newWheelJoint(b1, b2, x1, y1, x2, y2, ax, ay, collide)
    if type(ay) ~= 'number' then
        collide = ay
        ax, ay = x2, y2
        x2, y2 = x1, y1
    end
    return create('wheel', b1, b2, down(x1), down(y1), down(x2), down(y2), ax, ay, flag(collide))
end

function M.newFrictionJoint(b1, b2, x1, y1, x2, y2, collide)
    if shared(x2) then
        collide = x2
        x2, y2 = x1, y1
    end
    return create('friction', b1, b2, down(x1), down(y1), down(x2), down(y2), flag(collide))
end

function M.newMotorJoint(b1, b2, correction, collide)
    return create('motor', b1, b2, correction or 0.3, flag(collide))
end

function M.newPulleyJoint(b1, b2, gx1, gy1, gx2, gy2, x1, y1, x2, y2, ratio, collide)
    return create('pulley', b1, b2, down(gx1), down(gy1), down(gx2), down(gy2), down(x1), down(y1),
        down(x2), down(y2), ratio or 1, flag(collide))
end

function M.newGearJoint(j1, j2, ratio, collide)
    local world = j1._world
    local handle = B().kb2_joint_gear(world._h, j1._h, j2._h, ratio or 1, flag(collide))
    local joint = newJoint(world, handle, j1._a, j2._a)
    joint._gear = { j1, j2 }
    return joint
end

function M.newMouseJoint(body, x, y)
    local world = body._world
    local handle = B().kb2_joint_mouse(world._h, body._h, down(x), down(y), 1000 * body:getMass())
    return newJoint(world, handle, body)
end

function Joint:getType()
    return jointTypes[B().kb2_joint_type(self._h)]
end

function Joint:getBodies()
    return self._a, self._b or nil
end

function Joint:getAnchors()
    B().kb2_joint_anchors(self._h, quad)
    return up(quad[0]), up(quad[1]), up(quad[2]), up(quad[3])
end

function Joint:getReactionForce(dt)
    B().kb2_joint_reaction(self._h, dt ~= 0 and 1 / dt or 0, six)
    return up(six[0]), up(six[1])
end

function Joint:getReactionTorque(dt)
    B().kb2_joint_reaction(self._h, dt ~= 0 and 1 / dt or 0, six)
    return up(up(six[2]))
end

function Joint:getCollideConnected()
    return
    B().kb2_joint_collide(self._h) ~= 0
end

function Joint:setUserData(data)
    self._userdata = data
end

function Joint:getUserData()
    return self._userdata
end

function Joint:isDestroyed()
    return self._destroyed == true
end

function Joint:getJoints()
    return unpack(self._gear or {})
end

function Joint:destroy()
    if self._destroyed then return false end
    assert(not self._world:isLocked(), 'Cannot destroy a joint while the world is locked')
    B().kb2_joint_destroy(self._world._h, self._h)
    self._destroyed = true
    self._world._joints[self] = nil
    self._a._joints[self] = nil
    if self._b then self._b._joints[self] = nil end
    Registry.unregister(self._id)
    return true
end

M.class = Joint

return M
