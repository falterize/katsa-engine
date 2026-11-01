-- Weld: rigid join, optionally softened by frequency/damping.
return function(self, c)
    local joint = c.p.newWeldJoint(c.r0, c.r1, c.x0, c.y0, c.x1, c.y1, c.collide)
    joint:setFrequency(self.frequency)
    joint:setDampingRatio(self.dampingRatio)
    return joint
end
