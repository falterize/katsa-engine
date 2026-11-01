-- Prismatic: sliding along one axis with optional limits and motor.
return function(self, c)
    local f = c.f
    local joint =
        c.p.newPrismaticJoint(c.r0, c.r1, c.x0, c.y0, c.x1, c.y1, c.ax, c.ay, c.collide)
    joint:setLimits(self.lowerLimit * f, self.upperLimit * f)
    joint:setLimitsEnabled(self.limitsEnabled == true)
    joint:setMotorSpeed(self.motorSpeed * f)
    joint:setMaxMotorForce(self.motorForce * f)
    joint:setMotorEnabled(self.motorEnabled == true)
    return joint
end
