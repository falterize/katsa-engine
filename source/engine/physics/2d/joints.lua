local Joints = {}
local settings = {
    'enabled',
    'limitsEnabled',
    'lowerLimit',
    'upperLimit',
    'motorEnabled',
    'motorSpeed',
    'motorForce',
    'length',
    'maxLength',
    'frequency',
    'dampingRatio',
    'allowCollision',
    'maxForce',
    'maxTorque',
    'ratio',
    'joint0',
    'joint1',
    'angularOffset',
    'correctionFactor',
}

local function endpoint(attachment, physics)
    if not attachment or attachment.destroyed then
        return
    end
    assert(attachment:isA('Attachment2D'), 'Constraint2D endpoints require Attachment2D')
    local owner = attachment.parent
    while owner and not owner.body do
        owner = owner.parent
    end
    if not owner or owner.body.destroyed then
        return
    end
    assert(owner.body.physics == physics, 'Constraint2D cannot join different physics worlds')
    local x, y, angle = attachment:getWorldPose()
    local ox, oy, oa = owner:getWorldPose()
    local c, s = math.cos(math.rad(-oa)), math.sin(math.rad(-oa))
    local dx, dy, f = x - ox, y - oy, physics.factor
    local lx, ly = (dx * c - dy * s) * f, (dx * s + dy * c) * f
    x, y = owner.body.raw:getWorldPoint(lx, ly)
    return owner.body, x / f, y / f, angle - oa + math.deg(owner.body.raw:getAngle())
end

local function create(self, a, b, x0, y0, x1, y1, angle)
    local f, p, collide = self.physics.factor, katsa.physics, self.allowCollision == true
    local r0, r1 = a.raw, b.raw
    local joint, kind = nil, self.kind
    x0, y0, x1, y1 = x0 * f, y0 * f, x1 * f, y1 * f
    local ax, ay = math.cos(math.rad(angle)), math.sin(math.rad(angle))
    if kind == 'Hinge' then
        joint = p.newRevoluteJoint(r0, r1, x0, y0, x1, y1, collide)
        joint:setLimits(math.rad(self.lowerLimit), math.rad(self.upperLimit))
        joint:setLimitsEnabled(self.limitsEnabled == true)
        joint:setMotorSpeed(math.rad(self.motorSpeed))
        joint:setMaxMotorTorque(self.motorForce * f * f)
        joint:setMotorEnabled(self.motorEnabled == true)
    elseif kind == 'Prismatic' then
        joint = p.newPrismaticJoint(r0, r1, x0, y0, x1, y1, ax, ay, collide)
        joint:setLimits(self.lowerLimit * f, self.upperLimit * f)
        joint:setLimitsEnabled(self.limitsEnabled == true)
        joint:setMotorSpeed(self.motorSpeed * f)
        joint:setMaxMotorForce(self.motorForce * f)
        joint:setMotorEnabled(self.motorEnabled == true)
    elseif kind == 'Weld' then
        joint = p.newWeldJoint(r0, r1, x0, y0, x1, y1, collide)
        joint:setFrequency(self.frequency)
        joint:setDampingRatio(self.dampingRatio)
    elseif kind == 'Rope' then
        joint = p.newRopeJoint(
            r0,
            r1,
            x0,
            y0,
            x1,
            y1,
            (self.maxLength or self.length or math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / f) * f,
            collide
        )
    elseif kind == 'Distance' or kind == 'Spring' then
        joint = p.newDistanceJoint(r0, r1, x0, y0, x1, y1, collide)
        if self.length then
            joint:setLength(self.length * f)
        end
        joint:setFrequency(kind == 'Spring' and self.frequency or 0)
        joint:setDampingRatio(self.dampingRatio)
    elseif kind == 'Wheel' then
        joint = p.newWheelJoint(r0, r1, x0, y0, x1, y1, ax, ay, collide)
        joint:setSpringFrequency(self.frequency)
        joint:setSpringDampingRatio(self.dampingRatio)
        joint:setMotorSpeed(math.rad(self.motorSpeed))
        joint:setMaxMotorTorque(self.motorForce * f * f)
        joint:setMotorEnabled(self.motorEnabled == true)
    elseif kind == 'Friction' then
        joint = p.newFrictionJoint(r0, r1, x0, y0, x1, y1, collide)
        joint:setMaxForce(self.maxForce * f)
        joint:setMaxTorque(self.maxTorque * f * f)
    elseif kind == 'Motor' then
        joint = p.newMotorJoint(r0, r1, self.correctionFactor or 0.3, collide)
        if self.linearOffset then
            joint:setLinearOffset(self.linearOffset[1] * f, self.linearOffset[2] * f)
        end
        if self.angularOffset then
            joint:setAngularOffset(math.rad(self.angularOffset))
        end
        joint:setMaxForce(self.maxForce * f)
        joint:setMaxTorque(self.maxTorque * f * f)
    elseif kind == 'Pulley' then
        local g0 = assert(self.groundAnchor0, 'PulleyConstraint2D requires groundAnchor0')
        local g1 = assert(self.groundAnchor1, 'PulleyConstraint2D requires groundAnchor1')
        joint = p.newPulleyJoint(
            r0,
            r1,
            g0[1] * f,
            g0[2] * f,
            g1[1] * f,
            g1[2] * f,
            x0,
            y0,
            x1,
            y1,
            self.ratio,
            collide
        )
    elseif kind == 'Gear' then
        assert(
            self.joint0
                and self.joint1
                and self.joint0.physics == self.physics
                and self.joint1.physics == self.physics,
            'GearConstraint2D requires two local constraints'
        )
        assert(self.joint0.joint and self.joint1.joint, 'Gear source joints must be active')
        joint = p.newGearJoint(self.joint0.joint, self.joint1.joint, self.ratio, collide)
    elseif kind == 'Mouse' then
        local target = self.target or { x1 / f, y1 / f }
        joint = p.newMouseJoint(r1, target[1] * f, target[2] * f)
        joint:setMaxForce(self.maxForce * f)
        joint:setFrequency(self.frequency)
        joint:setDampingRatio(self.dampingRatio)
    else
        error('Unsupported Constraint2D kind: ' .. tostring(kind))
    end
    return joint
end

function Joints.step(self)
    if self.destroyed or self.enabled == false or self.broken then
        self:releaseJoint()
        self.status = self.broken and 'Broken' or 'Disabled'
        return
    end
    local a, x0, y0, angle = endpoint(
        self.attachment0 or self.kind == 'Gear' and self.joint0 and self.joint0.attachment1,
        self.physics
    )
    local b, x1, y1 = endpoint(
        self.attachment1 or self.kind == 'Gear' and self.joint1 and self.joint1.attachment1,
        self.physics
    )
    if self.kind == 'Mouse' and b and not a then
        a, x0, y0, angle = b, x1, y1, 0
    end
    if not a or not b or a == b and self.kind ~= 'Mouse' then
        self:releaseJoint()
        self.status = 'Waiting for two distinct bodies'
        return
    end
    if self.kind == 'Gear' then
        local j0, j1 = self.joint0, self.joint1
        if not j0 or not j1 or j0.destroyed or j1.destroyed or not j0.joint or not j1.joint then
            self:releaseJoint()
            self.status = 'Waiting for source joints'
            return
        end
        assert(
            (j0.kind == 'Hinge' or j0.kind == 'Prismatic')
                and (j1.kind == 'Hinge' or j1.kind == 'Prismatic'),
            'GearConstraint2D sources must be hinge or prismatic constraints'
        )
    end
    -- Compare local anchors: world-space motion must not recreate a live joint.
    local f = self.physics.factor
    local lx0, ly0 = a.raw:getLocalPoint(x0 * f, y0 * f)
    local lx1, ly1 = b.raw:getLocalPoint(x1 * f, y1 * f)
    local inputs, count, changed =
        self._jointInputs or {}, 0, not self.joint or self.joint:isDestroyed()
    local function input(value)
        count = count + 1
        local previous = inputs[count]
        if type(value) == 'number' and type(previous) == 'number' then
            changed = math.abs(previous - value) > 0.0001 or changed
        else
            changed = previous ~= value or changed
        end
        inputs[count] = value
    end
    input(a)
    input(b)
    input(lx0)
    input(ly0)
    input(lx1)
    input(ly1)
    input(angle - math.deg(a.raw:getAngle()))
    for _, name in ipairs(settings) do
        input(self[name] == nil and 'default' or self[name])
    end
    for _, name in ipairs({ 'groundAnchor0', 'groundAnchor1', 'linearOffset' }) do
        local v = self[name] or {}
        input(v[1] or 0)
        input(v[2] or 0)
    end
    if self.kind == 'Gear' then
        input(self.joint0 and self.joint0.joint)
        input(self.joint1 and self.joint1.joint)
    end
    if changed then
        self:releaseJoint()
        self.joint = create(self, a, b, x0, y0, x1, y1, angle)
        self._jointInputs, self._body0, self._body1 = inputs, a, b
    end
    if self.kind == 'Mouse' and self.target then
        self.joint:setTarget(self.target[1] * f, self.target[2] * f)
    end
    self.status = 'Active'
end

function Joints.checkBreak(self, dt)
    if not self.joint or self.joint:isDestroyed() then
        return
    end
    local f = self.physics.factor
    local x, y = self.joint:getReactionForce(1 / dt)
    self.reactionForce = math.sqrt(x * x + y * y) / f
    self.reactionTorque = math.abs(self.joint:getReactionTorque(1 / dt)) / (f * f)
    if
        self.breakForce > 0 and self.reactionForce > self.breakForce
        or self.breakTorque > 0 and self.reactionTorque > self.breakTorque
    then
        self.broken = true
        self:releaseJoint()
        self.status = 'Broken'
        self:emit('broken', self.reactionForce, self.reactionTorque)
    end
end

return Joints
