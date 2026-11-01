-- Rope: maximum distance between two anchors.
return function(self, c)
    local length = self.maxLength
        or self.length
        or math.sqrt((c.x1 - c.x0) ^ 2 + (c.y1 - c.y0) ^ 2) / c.f
    return c.p.newRopeJoint(c.r0, c.r1, c.x0, c.y0, c.x1, c.y1, length * c.f, c.collide)
end
