-- Wheel: axis suspension spring with rotation motor.
return function(self, c)
    local f = c.f
    local joint = c.p.newWheelJoint(c.r0, c.r1, c.x0, c.y0, c.x1, c.y1, c.ax, c.ay, c.collide)
    joint:setSpringFrequency(self.frequency)
    joint:setSpringDampingRatio(self.dampingRatio)
    joint:setMotorSpeed(math.rad(self.motorSpeed))
    joint:setMaxMotorTorque(self.motorForce * f * f)
    joint:setMotorEnabled(self.motorEnabled == true)
    return joint
end
