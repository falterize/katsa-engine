-- Mouse: spring that drags a body toward a target point.
return function(self, c)
    local f = c.f
    local target = self.target or { c.x1 / f, c.y1 / f }
    local joint = c.p.newMouseJoint(c.r1, target[1] * f, target[2] * f)
    joint:setMaxForce(self.maxForce * f)
    joint:setFrequency(self.frequency)
    joint:setDampingRatio(self.dampingRatio)
    return joint
end
