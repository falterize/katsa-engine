-- Aims a bone, or a chain of bones (spine -> neck -> head), at a target.
--
--   IK.LookAt.new({ bones = { 'Spine2', 'Neck', 'Head' }, weights = { 0.2, 0.3, 0.5 },
--                   target = camera, forward = { 0, 0, 1 }, maxAngle = 70, speed = 8 })
--
-- `forward` is the bone-local axis that should face the target (the direction the head looks).
-- `weights` split the turn across the chain; each bone takes its share of what is still left.
-- `maxAngle` (degrees) limits how far the aim may leave the animated direction, `speed` smooths
-- target changes (1/second; nil = instant).
local Quat = require('../quat')
local Modifier = require('../modifier')

local LookAt = Modifier.extend()

function LookAt.new(settings)
    local self = setmetatable({}, LookAt)
    self:configure(settings)
    self.chain = settings.bones or { settings.bone }
    assert(self.chain[1], 'LookAt needs `bone` or `bones`')
    self.weights = settings.weights
    self.forward = settings.forward or { 0, 0, 1 }
    self.maxAngle = settings.maxAngle
    self.speed = settings.speed
    return self
end

function LookAt:bones()
    return self.chain
end

function LookAt:solve(skeleton, dt)
    local tx, ty, tz = self:modelPoint(skeleton, self.target)
    if not tx then
        self._smooth = nil
        return
    end
    if self.speed and self.speed > 0 and self._smooth then
        local k = 1 - math.exp(-self.speed * dt)
        local s = self._smooth
        s[1], s[2], s[3] = s[1] + (tx - s[1]) * k, s[2] + (ty - s[2]) * k, s[3] + (tz - s[3]) * k
        tx, ty, tz = s[1], s[2], s[3]
    else
        self._smooth = { tx, ty, tz }
    end
    local count = #self.chain
    local weights, remaining = {}, 0
    for i = 1, count do
        weights[i] = self.weights and self.weights[i] or 1
        remaining = remaining + weights[i]
    end
    if remaining <= 0 then
        return
    end
    local fx, fy, fz = self.forward[1], self.forward[2], self.forward[3]
    local limit, desired = self.maxAngle and math.rad(self.maxAngle), nil
    for i, name in ipairs(self.chain) do
        local px, py, pz = skeleton:getPosition(name)
        local rotation = skeleton:getRotation(name)
        local dx, dy, dz = Quat.rotate(rotation, fx, fy, fz)
        if not desired then
            -- Limit the aim once, against the animated facing of the first bone.
            local delta = Quat.fromTo(dx, dy, dz, tx - px, ty - py, tz - pz)
            local angle = Quat.angle(delta)
            if limit and angle > limit then
                delta = Quat.scale(delta, limit / angle, {})
            end
            local ex, ey, ez = Quat.rotate(delta, dx, dy, dz)
            desired = { ex, ey, ez }
        end
        local delta = Quat.fromTo(dx, dy, dz, desired[1], desired[2], desired[3])
        local share = weights[i] / remaining
        remaining = remaining - weights[i]
        skeleton:rotate(name, Quat.scale(delta, math.min(1, share), {}))
    end
end

return LookAt
