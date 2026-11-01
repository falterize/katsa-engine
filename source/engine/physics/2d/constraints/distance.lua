-- Distance and Spring: fixed or damped-spring distance between two anchors.
return function(self, c)
    local joint = c.p.newDistanceJoint(c.r0, c.r1, c.x0, c.y0, c.x1, c.y1, c.collide)
    if self.length then
        joint:setLength(self.length * c.f)
    end
    joint:setFrequency(self.kind == 'Spring' and self.frequency or 0)
    joint:setDampingRatio(self.dampingRatio)
    return joint
end
