-- Forward kinematics: poses bones by angles instead of a target.
--
--   -- curl a finger / tail: every bone of the chain turns by `rotation`, scaled by `falloff` per joint
--   IK.FK.new({ bones = { 'Finger1', 'Finger2', 'Finger3' }, rotation = { 40, 0, 0 }, falloff = 0.8 })
--   -- or pose named bones directly
--   IK.FK.new({ pose = { Head = { 0, 25, 0 }, Spine1 = { 5, 0, 0 } } })
--
-- Angles are euler degrees applied in Z * Y * X order in the bone's local space. `mode`:
--   'Additive'  turns the bone on top of the animated pose (default)
--   'FromRest'  ignores the animation: rest rotation turned by the angles
local Quat = require('../quat')
local Modifier = require('../modifier')

local FK = Modifier.extend()

function FK.new(settings)
    return setmetatable({}, FK):read(settings)
end

function FK:read(settings)
    self:configure(settings)
    self.chain = settings.bones or {}
    self.rotation = settings.rotation or { 0, 0, 0 }
    self.falloff = settings.falloff or 1
    self.mode = settings.mode or 'Additive'
    self.pose = settings.pose
    assert(
        self.mode == 'Additive' or self.mode == 'FromRest',
        'FK mode must be Additive or FromRest'
    )
    return self
end

function FK:bones()
    local list = {}
    for _, name in ipairs(self.chain) do
        list[#list + 1] = name
    end
    for name in pairs(self.pose or {}) do
        list[#list + 1] = name
    end
    return list
end

-- Euler degrees (Z * Y * X) to a quaternion.
function FK.euler(x, y, z, out)
    local qx = Quat.axisAngle(1, 0, 0, math.rad(x))
    local qy = Quat.axisAngle(0, 1, 0, math.rad(y))
    local qz = Quat.axisAngle(0, 0, 1, math.rad(z))
    return Quat.multiply(Quat.multiply(qz, qy), qx, out)
end

local function turn(self, skeleton, name, q)
    local node = skeleton:resolve(name)
    local base = self.mode == 'FromRest' and node.rest.rotation or node.rotation
    skeleton:setLocalRotation(name, Quat.multiply(base, q, {}))
end

function FK:solve(skeleton)
    local r = self.rotation
    local factor = 1
    for _, name in ipairs(self.chain) do
        if r[1] ~= 0 or r[2] ~= 0 or r[3] ~= 0 or self.mode == 'FromRest' then
            turn(self, skeleton, name, FK.euler(r[1] * factor, r[2] * factor, r[3] * factor))
        end
        factor = factor * self.falloff
    end
    for name, angles in pairs(self.pose or {}) do
        turn(self, skeleton, name, FK.euler(angles[1], angles[2], angles[3]))
    end
end

return FK
