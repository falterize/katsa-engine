-- CCD (Cyclic Coordinate Descent): rotates one joint at a time, from the bone before the tip back
-- to the root, so the tip approaches the target. Slower to converge than FABRIK but it supports
-- per-joint limits, which makes it the right solver for constrained limbs and tails.
--
--   IK.Ccd.new({ bones = { 'Shoulder', 'Elbow', 'Wrist', 'Hand' }, target = node,
--                iterations = 12, tolerance = 0.001, maxStep = 20,
--                limits = { Elbow = 140, Wrist = 60 } })
--
-- `maxStep` caps the rotation per joint per iteration (degrees); `limits` caps how far a joint's
-- local rotation may leave the animated pose (degrees, by bone name); `limit` applies one
-- angle to every joint.
local Quat = require('../quat')
local Modifier = require('../modifier')

local Ccd = Modifier.extend()

function Ccd.new(settings)
    return setmetatable({}, Ccd):read(settings)
end

function Ccd:read(settings)
    self:configure(settings)
    self.chain = settings.bones
    assert(self.chain and #self.chain >= 2, 'Ccd needs a `bones` chain of at least two bones')
    self.iterations = settings.iterations or 10
    self.tolerance = settings.tolerance or 0.001
    self.maxStep = settings.maxStep
    self.limits = settings.limits or {}
    self.limit = settings.limit
    return self
end

function Ccd:bones()
    return self.chain
end

function Ccd:solve(skeleton)
    local tx, ty, tz = self:modelPoint(skeleton, self.target)
    if not tx then
        return
    end
    local count = #self.chain
    local base = {}
    for i = 1, count do
        base[i] = skeleton:getLocalRotation(self.chain[i])
    end
    local maxStep = self.maxStep and math.rad(self.maxStep)
    local tip = self.chain[count]
    for _ = 1, self.iterations do
        local cx, cy, cz = skeleton:getPosition(tip)
        if (cx - tx) ^ 2 + (cy - ty) ^ 2 + (cz - tz) ^ 2 <= self.tolerance ^ 2 then
            break
        end
        for i = count - 1, 1, -1 do
            local name = self.chain[i]
            local jx, jy, jz = skeleton:getPosition(name)
            cx, cy, cz = skeleton:getPosition(tip)
            local delta = Quat.fromTo(cx - jx, cy - jy, cz - jz, tx - jx, ty - jy, tz - jz)
            local angle = Quat.angle(delta)
            if maxStep and angle > maxStep then
                delta = Quat.scale(delta, maxStep / angle, {})
            end
            skeleton:rotate(name, delta)
            local limit = self.limits[name] or self.limit
            if limit and limit > 0 then
                skeleton:limitLocal(name, base[i], math.rad(limit))
            end
        end
    end
end

return Ccd
