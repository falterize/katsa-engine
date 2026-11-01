-- Pulley: two bodies hang from ground anchors with a length ratio.
return function(self, c)
    local f = c.f
    local g0 = assert(self.groundAnchor0, 'PulleyConstraint2D requires groundAnchor0')
    local g1 = assert(self.groundAnchor1, 'PulleyConstraint2D requires groundAnchor1')
    return c.p.newPulleyJoint(
        c.r0,
        c.r1,
        g0[1] * f,
        g0[2] * f,
        g1[1] * f,
        g1[2] * f,
        c.x0,
        c.y0,
        c.x1,
        c.y1,
        self.ratio,
        c.collide
    )
end
