-- Hinge: one rotation point with optional limits and motor.
return function(self, c)
    local f = c.f
    local joint = c.p.newRevoluteJoint(c.r0, c.r1, c.x0, c.y0, c.x1, c.y1, c.collide)
    joint:setLimits(math.rad(self.lowerLimit), math.rad(self.upperLimit))
    joint:setLimitsEnabled(self.limitsEnabled == true)
    joint:setMotorSpeed(math.rad(self.motorSpeed))
    joint:setMaxMotorTorque(self.motorForce * f * f)
    joint:setMotorEnabled(self.motorEnabled == true)
    return joint
end
