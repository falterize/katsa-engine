-- Friction: top-down linear and angular drag between two bodies.
return function(self, c)
    local f = c.f
    local joint = c.p.newFrictionJoint(c.r0, c.r1, c.x0, c.y0, c.x1, c.y1, c.collide)
    joint:setMaxForce(self.maxForce * f)
    joint:setMaxTorque(self.maxTorque * f * f)
    return joint
end
