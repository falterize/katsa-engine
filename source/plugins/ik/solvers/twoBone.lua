-- Analytic two-bone IK (arm or leg): rotates `root` and `mid` so `tip` reaches `target`, bending
-- toward `pole`. Out-of-reach targets stretch the limb straight toward the target.
--
--   IK.TwoBone.new({ root = 'UpperArm', mid = 'LowerArm', tip = 'Hand',
--                    target = node, pole = elbowHint, softness = 0.1 })
--
-- `softness` (model units) eases the last stretch before full extension so the knee does not
-- snap straight. Without a pole the limb keeps the bend direction of the animation.
local Modifier = require('../modifier')

local TwoBone = Modifier.extend()

local EPSILON = 1e-6

function TwoBone.new(settings)
    return setmetatable({}, TwoBone):read(settings)
end

function TwoBone:read(settings)
    self:configure(settings)
    self.rootBone, self.midBone, self.tipBone = settings.root, settings.mid, settings.tip
    assert(self.rootBone and self.midBone and self.tipBone, 'TwoBone needs root, mid and tip bones')
    self.softness = settings.softness or 0
    return self
end

function TwoBone:bones()
    return { self.rootBone, self.midBone, self.tipBone }
end

local function normalize(x, y, z)
    local length = math.sqrt(x * x + y * y + z * z)
    if length < EPSILON then
        return 0, 0, 0, 0
    end
    return x / length, y / length, z / length, length
end

function TwoBone:solve(skeleton)
    local tx, ty, tz = self:modelPoint(skeleton, self.target)
    if not tx then
        return
    end
    local ax, ay, az = skeleton:getPosition(self.rootBone)
    local bx, by, bz = skeleton:getPosition(self.midBone)
    local cx, cy, cz = skeleton:getPosition(self.tipBone)
    local l1 = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2)
    local l2 = math.sqrt((cx - bx) ^ 2 + (cy - by) ^ 2 + (cz - bz) ^ 2)
    if l1 < EPSILON or l2 < EPSILON then
        return
    end
    local ux, uy, uz, distance = normalize(tx - ax, ty - ay, tz - az)
    if distance < EPSILON then
        return
    end
    local maximum, minimum = l1 + l2, math.abs(l1 - l2)
    local reach = distance
    local soft = math.min(self.softness, maximum * 0.5)
    if soft > 0 and reach > maximum - soft then
        reach = maximum - soft + soft * (1 - math.exp(-(reach - (maximum - soft)) / soft))
    end
    reach = math.max(minimum + EPSILON, math.min(maximum - EPSILON, reach))
    -- Law of cosines gives the angle at the root between the target line and the upper bone.
    local cosine = math.max(-1, math.min(1, (l1 * l1 + reach * reach - l2 * l2) / (2 * l1 * reach)))
    local sine = math.sqrt(1 - cosine * cosine)
    -- Bend direction: pole (or the animated bend) with the target axis removed.
    local px, py, pz
    local hx, hy, hz = self:modelPoint(skeleton, self.pole)
    if hx then
        px, py, pz = hx - ax, hy - ay, hz - az
    else
        px, py, pz = bx - ax, by - ay, bz - az
    end
    local along = px * ux + py * uy + pz * uz
    px, py, pz = px - ux * along, py - uy * along, pz - uz * along
    local length
    px, py, pz, length = normalize(px, py, pz)
    if length == 0 then
        -- Fully straight animation without a pole: bend perpendicular to the axis.
        local dot = uy
        px, py, pz = normalize(-ux * dot, 1 - uy * dot, -uz * dot)
        if px == 0 and py == 0 and pz == 0 then
            px, py, pz = 1, 0, 0
        end
    end
    local midX = ax + ux * l1 * cosine + px * l1 * sine
    local midY = ay + uy * l1 * cosine + py * l1 * sine
    local midZ = az + uz * l1 * cosine + pz * l1 * sine
    skeleton:aim(self.rootBone, self.midBone, midX, midY, midZ)
    skeleton:aim(self.midBone, self.tipBone, ax + ux * reach, ay + uy * reach, az + uz * reach)
end

return TwoBone
