-- Translate scene constraint properties into the stable Lua configuration API.
-- Backend adapters map this description to their own native joint classes.
local unpack = require('source.engine.math.array').unpack

local Settings = {}

function Settings.build(self, p0, p1, x0, x1, y0, y1)
    local O = self._world.physics.valueTypes
    local settings = {
        anchor1 = p0,
        anchor2 = p1,
        allowCollision = self.allowCollision == true,
        breakForce = self.breakForce,
        breakTorque = self.breakTorque,
    }
    local axis0, axis1 = O.Vec3.new(unpack(x0)), O.Vec3.new(unpack(x1))
    local kind = self.kind
    if
        kind == 'Revolute'
        or kind == 'Prismatic'
        or kind == 'Cylindrical'
        or kind == 'Universal'
    then
        settings.localAxis1 = axis0
        settings.localAxis2 = axis1
    end
    local rotational = kind ~= 'Prismatic'
    local lm = (rotational and O.RotationalLimitMotor or O.TranslationalLimitMotor).new()
    local unit = rotational and math.pi / 180 or 1 / self._world.physics.units
    lm:setLimits(self.lowerLimit * unit, self.upperLimit * unit)
    lm:setMotor(self.motorSpeed * unit, self.motorForce)
    local sd = O.SpringDamper.new()
    sd:setSpring(self.frequency, self.dampingRatio)
    if kind == 'Revolute' or kind == 'Prismatic' then
        settings.limitMotor = lm
        settings.springDamper = sd
    end
    if kind == 'Cylindrical' then
        settings.rotationalLimitMotor = lm
        settings.rotationalSpringDamper = sd
    end
    if kind == 'Universal' then
        settings.limitMotor1 = lm
        settings.limitMotor2 = lm
        settings.springDamper1 = sd
        settings.springDamper2 = sd
    end
    if kind == 'Spherical' then
        settings.springDamper = sd
    end
    if kind == 'Ragdoll' then
        settings.localTwistAxis1 = axis0
        settings.localTwistAxis2 = axis1
        settings.localSwingAxis1 = O.Vec3.new(unpack(y0))
        settings.localSwingAxis2 = O.Vec3.new(unpack(y1))
        settings.twistLimitMotor = lm
        settings.maxSwingAngle1 = math.rad(self.upperLimit)
        settings.maxSwingAngle2 = math.rad(self.upperLimit)
    end
    if kind == 'Generic' then
        local function basis(x, y)
            local z =
                { x[2] * y[3] - x[3] * y[2], x[3] * y[1] - x[1] * y[3], x[1] * y[2] - x[2] * y[1] }
            return O.Mat3.new(x[1], y[1], z[1], x[2], y[2], z[2], x[3], y[3], z[3])
        end
        settings.localBasis1 = basis(x0, y0)
        settings.localBasis2 = basis(x1, y1)

        local config = O.GenericJointConfig.new()
        for i = 0, 2 do
            config.translationalLimitMotors[i]:setLimits(
                self.translationLower[i + 1] / self._world.physics.units,
                self.translationUpper[i + 1] / self._world.physics.units
            )
            config.rotationalLimitMotors[i]:setLimits(
                math.rad(self.rotationLower[i + 1]),
                math.rad(self.rotationUpper[i + 1])
            )
        end
        settings.translationalLimitMotors = config.translationalLimitMotors
        settings.rotationalLimitMotors = config.rotationalLimitMotors
    end

    return settings
end

return Settings
