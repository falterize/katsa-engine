-- Gear: couples two active hinge/prismatic constraints by a ratio.
return function(self, c)
    assert(
        self.joint0
            and self.joint1
            and self.joint0.physics == self.physics
            and self.joint1.physics == self.physics,
        'GearConstraint2D requires two local constraints'
    )
    assert(self.joint0.joint and self.joint1.joint, 'Gear source joints must be active')
    return c.p.newGearJoint(self.joint0.joint, self.joint1.joint, self.ratio, c.collide)
end
