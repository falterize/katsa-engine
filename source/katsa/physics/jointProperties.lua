-- Joint scalar properties (limits, motors, springs) shared by all joint types.

local Binding = require('source.katsa.physics.binding')
local Scale = require('source.katsa.physics.scale')
local Object = require('source.katsa.physics.object')
local B = Binding.lib
local up = Scale.up
local down = Scale.down
local square = Scale.square
local squareDown = Scale.squareDown
local pair = Binding.pair
local alive = Object.alive

-- Scalar property codes are shared with native/src/box2d/bridge.h (JointProperty, kb2_joint_get/set).
local function install(Joint)
    local function prop(name, what, convert, restore, setter)
        Joint['get' .. name] = function(self)
            alive(self, 'Joint')
            local v = B().kb2_joint_get(self._h, what)
            return restore and restore(v) or v
        end
        if setter ~= false then
            Joint['set' .. name] = function(self, value)
                alive(self, 'Joint')
                B().kb2_joint_set(self._h, what, convert and convert(value) or value)
            end
        end
    end
    local function square(v)
        return up(up(v))
    end
    local function squareDown(v)
        return down(down(v))
    end
    local function bool(v)
        return v and 1 or 0
    end

    prop('JointAngle', 0, nil, nil, false)
    prop('JointTranslation', 0, nil, up, false)
    prop('JointSpeed', 1, nil, nil, false)
    prop('MotorSpeed', 6)
    prop('SpringFrequency', 9)
    prop('SpringDampingRatio', 10)
    prop('Frequency', 9)
    prop('DampingRatio', 10)
    prop('Length', 11, down, up)
    prop('MaxLength', 11, down, up)
    prop('CorrectionFactor', 14)
    prop('AngularOffset', 15)
    prop('Ratio', 18)
    prop('ReferenceAngle', 8, nil, nil, false)

    function Joint:getJointAngle()
        return B().kb2_joint_get(self._h, 0)
    end

    function Joint:getJointTranslation()
        return up(B().kb2_joint_get(self._h, 0))
    end

    function Joint:isLimitsEnabled()
        return B().kb2_joint_get(self._h, 2) ~= 0
    end

    function Joint:areLimitsEnabled()
        return B().kb2_joint_get(self._h, 2) ~= 0
    end

    function Joint:setLimitsEnabled(v)
        B().kb2_joint_set(self._h, 2, bool(v))
    end

    function Joint:getLowerLimit()
        local v = B().kb2_joint_get(self._h, 3)
        return self:getType() == 'prismatic' and up(v) or v
    end

    function Joint:getUpperLimit()
        local v = B().kb2_joint_get(self._h, 4)
        return self:getType() == 'prismatic' and up(v) or v
    end

    function Joint:getLimits()
        return self:getLowerLimit(), self:getUpperLimit()
    end

    function Joint:setLimits(lower, upper)
        if self:getType() == 'prismatic' then
            lower, upper = down(lower), down(upper)
        end
        B().kb2_joint_set_limits(self._h, lower, upper)
    end

    function Joint:setLowerLimit(v)
        self:setLimits(v, self:getUpperLimit())
    end

    function Joint:setUpperLimit(v)
        self:setLimits(self:getLowerLimit(), v)
    end

    function Joint:isMotorEnabled()
        return B().kb2_joint_get(self._h, 5) ~= 0
    end

    function Joint:setMotorEnabled(v)
        B().kb2_joint_set(self._h, 5, bool(v))
    end

    function Joint:getMotorSpeed()
        local v = B().kb2_joint_get(self._h, 6)
        return self:getType() == 'prismatic' and up(v) or v
    end

    function Joint:setMotorSpeed(v)
        B().kb2_joint_set(self._h, 6, self:getType() == 'prismatic' and down(v) or v)
    end

    function Joint:getMaxMotorTorque()
        return square(B().kb2_joint_get(self._h, 7))
    end

    function Joint:setMaxMotorTorque(v)
        B().kb2_joint_set(self._h, 7, squareDown(v))
    end

    function Joint:getMaxMotorForce()
        return up(B().kb2_joint_get(self._h, 7))
    end

    function Joint:setMaxMotorForce(v)
        B().kb2_joint_set(self._h, 7, down(v))
    end

    function Joint:getMotorTorque(dt)
        return self:getReactionTorque(dt)
    end

    function Joint:getMotorForce(dt)
        return 0
    end

    function Joint:getMaxForce()
        return up(B().kb2_joint_get(self._h, 12))
    end

    function Joint:setMaxForce(v)
        B().kb2_joint_set(self._h, 12, down(v))
    end

    function Joint:getMaxTorque()
        return square(B().kb2_joint_get(self._h, 13))
    end

    function Joint:setMaxTorque(v)
        B().kb2_joint_set(self._h, 13, squareDown(v))
    end

    function Joint:setLinearOffset(x, y)
        B().kb2_joint_set_vec(self._h, 0, down(x), down(y))
    end

    function Joint:getLinearOffset()
        B().kb2_joint_get_vec(self._h, 0, pair)
        return up(pair[0]), up(pair[1])
    end

    function Joint:setTarget(x, y)
        B().kb2_joint_set_vec(self._h, 1, down(x), down(y))
    end

    function Joint:getTarget()
        B().kb2_joint_get_vec(self._h, 1, pair)
        return up(pair[0]), up(pair[1])
    end

    function Joint:getGroundAnchors()
        B().kb2_joint_get_vec(self._h, 2, pair)
        local ax, ay = up(pair[0]), up(pair[1])
        B().kb2_joint_get_vec(self._h, 3, pair)
        return ax, ay, up(pair[0]), up(pair[1])
    end

    function Joint:getAxis()
        B().kb2_joint_get_vec(self._h, 4, pair)
        return pair[0], pair[1]
    end

    function Joint:getLengthA()
        return up(B().kb2_joint_get(self._h, 16))
    end

    function Joint:getLengthB()
        return up(B().kb2_joint_get(self._h, 17))
    end
end

return install
