local bodyOf = require('../bodyOf')
local Builders = require('./constraints')
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
    while owner and not bodyOf(owner) do
        owner = owner.parent
    end
    local body = bodyOf(owner)
    if not owner or body.destroyed then
        return
    end
    assert(body.space == physics, 'Constraint2D cannot join different physics worlds')
    local x, y, angle = attachment:getWorldPose()
    local ox, oy, oa = owner:getWorldPose()
    local c, s = math.cos(math.rad(-oa)), math.sin(math.rad(-oa))
    local dx, dy, f = x - ox, y - oy, physics.factor
    local lx, ly = (dx * c - dy * s) * f, (dx * s + dy * c) * f
    x, y = body.raw:getWorldPoint(lx, ly)
    return body, x / f, y / f, angle - oa + math.deg(body.raw:getAngle())
end

local function create(self, a, b, x0, y0, x1, y1, angle)
    local f = self.physics.factor
    local rad = math.rad(angle)
    return Builders.build(self, {
        f = f,
        p = katsa.physics,
        r0 = a.raw,
        r1 = b.raw,
        x0 = x0 * f,
        y0 = y0 * f,
        x1 = x1 * f,
        y1 = y1 * f,
        ax = math.cos(rad),
        ay = math.sin(rad),
        collide = self.allowCollision == true,
    })
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
