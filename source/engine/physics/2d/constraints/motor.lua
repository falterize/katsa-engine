-- Motor: drives one body toward an offset from another.
return function(self, c)
    local f = c.f
    local joint = c.p.newMotorJoint(c.r0, c.r1, self.correctionFactor or 0.3, c.collide)
    if self.linearOffset then
        joint:setLinearOffset(self.linearOffset[1] * f, self.linearOffset[2] * f)
    end
    if self.angularOffset then
        joint:setAngularOffset(math.rad(self.angularOffset))
    end
    joint:setMaxForce(self.maxForce * f)
    joint:setMaxTorque(self.maxTorque * f * f)
    return joint
end
