-- FABRIK (Forward And Backward Reaching IK) for chains of any length: tentacles, tails, spines,
-- arms with many joints. The first bone stays pinned and the last bone reaches for the target.
--
--   IK.Fabrik.new({ bones = { 'Spine', 'Spine1', 'Spine2', 'Neck' }, target = node,
--                   iterations = 12, tolerance = 0.001, pole = hint })
--
-- `tolerance` is in model units. `pole` (optional) twists the inner joints around the
-- root->tip axis toward it. Out-of-reach targets straighten the chain toward the target.
local Quat = require('../quat')
local Modifier = require('../modifier')

local Fabrik = Modifier.extend()

local EPSILON = 1e-9

function Fabrik.new(settings)
    return setmetatable({}, Fabrik):read(settings)
end

function Fabrik:read(settings)
    self:configure(settings)
    self.chain = settings.bones
    assert(self.chain and #self.chain >= 2, 'Fabrik needs a `bones` chain of at least two bones')
    self.iterations = settings.iterations or 10
    self.tolerance = settings.tolerance or 0.001
    return self
end

function Fabrik:bones()
    return self.chain
end

local function step(from, to, length)
    local dx, dy, dz = to[1] - from[1], to[2] - from[2], to[3] - from[3]
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < EPSILON then
        return { from[1], from[2], from[3] }
    end
    local k = length / d
    return { from[1] + dx * k, from[2] + dy * k, from[3] + dz * k }
end

function Fabrik:solve(skeleton)
    local tx, ty, tz = self:modelPoint(skeleton, self.target)
    if not tx then
        return
    end
    local count = #self.chain
    local points, lengths, total = {}, {}, 0
    for i, name in ipairs(self.chain) do
        local x, y, z = skeleton:getPosition(name)
        points[i] = { x, y, z }
    end
    for i = 1, count - 1 do
        local a, b = points[i], points[i + 1]
        lengths[i] = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
        total = total + lengths[i]
    end
    local root, target = { points[1][1], points[1][2], points[1][3] }, { tx, ty, tz }
    local distance = math.sqrt((tx - root[1]) ^ 2 + (ty - root[2]) ^ 2 + (tz - root[3]) ^ 2)
    if distance >= total then
        for i = 1, count - 1 do
            points[i + 1] = step(points[i], target, lengths[i])
        end
    else
        for _ = 1, self.iterations do
            local tip = points[count]
            local error = math.sqrt((tip[1] - tx) ^ 2 + (tip[2] - ty) ^ 2 + (tip[3] - tz) ^ 2)
            if error <= self.tolerance then
                break
            end
            points[count] = { tx, ty, tz }
            for i = count - 1, 1, -1 do
                points[i] = step(points[i + 1], points[i], lengths[i])
            end
            points[1] = { root[1], root[2], root[3] }
            for i = 1, count - 1 do
                points[i + 1] = step(points[i], points[i + 1], lengths[i])
            end
        end
    end
    local hx, hy, hz = self:modelPoint(skeleton, self.pole)
    if hx and count > 2 then
        -- Twist the inner joints about the root->tip axis so the chain bends toward the pole.
        local tip = points[count]
        local ax, ay, az = tip[1] - root[1], tip[2] - root[2], tip[3] - root[3]
        local length = math.sqrt(ax * ax + ay * ay + az * az)
        if length > EPSILON then
            ax, ay, az = ax / length, ay / length, az / length
            local function perpendicular(x, y, z)
                local along = x * ax + y * ay + z * az
                return x - ax * along, y - ay * along, z - az * along
            end
            local qx, qy, qz = perpendicular(hx - root[1], hy - root[2], hz - root[3])
            for i = 2, count - 1 do
                local p = points[i]
                local vx, vy, vz = perpendicular(p[1] - root[1], p[2] - root[2], p[3] - root[3])
                local twist = Quat.fromTo(vx, vy, vz, qx, qy, qz)
                -- Only the part of the arc about the chain axis may be applied.
                local dot = twist[1] * ax + twist[2] * ay + twist[3] * az
                local axial = Quat.normalize({ ax * dot, ay * dot, az * dot, twist[4] }, {})
                local rx, ry, rz = Quat.rotate(axial, p[1] - root[1], p[2] - root[2], p[3] - root[3])
                p[1], p[2], p[3] = root[1] + rx, root[2] + ry, root[3] + rz
            end
        end
    end
    -- Convert joint positions to bone rotations, root first; each aim sees the pose so far.
    for i = 1, count - 1 do
        local p = points[i + 1]
        skeleton:aim(self.chain[i], self.chain[i + 1], p[1], p[2], p[3])
    end
end

return Fabrik
