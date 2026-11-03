-- Jacobian IK (damped least squares) for chains with three rotation axes per joint. Every
-- iteration builds the Jacobian of the tip position with respect to each joint's x/y/z rotation and
-- solves for the smallest joint rotations that move the tip toward the target. It copes with
-- targets near singular poses better than CCD and moves all joints together, which looks
-- smoother on long chains (tentacles, spines, cranes).
--
--   IK.Jacobian.new({ bones = { 'Spine', 'Spine1', 'Spine2', 'Neck' }, target = node,
--                     iterations = 8, tolerance = 0.001, damping = 0.2, maxStep = 10 })
--
-- `damping` is relative to the chain length (higher = steadier, slower), `maxStep` caps each
-- joint rotation per iteration (degrees) and `limit` caps how far a joint may leave the
-- animated pose (degrees, 0 = unlimited).
local Quat = require('../quat')
local Modifier = require('../modifier')

local Jacobian = Modifier.extend()

function Jacobian.new(settings)
    return setmetatable({}, Jacobian):read(settings)
end

function Jacobian:read(settings)
    self:configure(settings)
    self.chain = settings.bones
    assert(self.chain and #self.chain >= 2, 'Jacobian needs a `bones` chain of at least two bones')
    self.iterations = settings.iterations or 8
    self.tolerance = settings.tolerance or 0.001
    self.damping = settings.damping or 0.2
    self.maxStep = settings.maxStep or 10
    self.limit = settings.limit
    return self
end

function Jacobian:bones()
    return self.chain
end

-- Solves the symmetric 3x3 system A y = e by Cramer's rule; nil when singular.
local function solve3(a, e)
    local a11, a12, a13, a22, a23, a33 = a[1], a[2], a[3], a[4], a[5], a[6]
    local det = a11 * (a22 * a33 - a23 * a23) - a12 * (a12 * a33 - a23 * a13)
        + a13 * (a12 * a23 - a22 * a13)
    if math.abs(det) < 1e-18 then
        return
    end
    local x = e[1] * (a22 * a33 - a23 * a23) - a12 * (e[2] * a33 - a23 * e[3])
        + a13 * (e[2] * a23 - a22 * e[3])
    local y = a11 * (e[2] * a33 - a23 * e[3]) - e[1] * (a12 * a33 - a23 * a13)
        + a13 * (a12 * e[3] - e[2] * a13)
    local z = a11 * (a22 * e[3] - e[2] * a23) - a12 * (a12 * e[3] - e[2] * a13)
        + e[1] * (a12 * a23 - a22 * a13)
    return x / det, y / det, z / det
end

local AXES = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

function Jacobian:solve(skeleton)
    local tx, ty, tz = self:modelPoint(skeleton, self.target)
    if not tx then
        return
    end
    local count = #self.chain
    local tip = self.chain[count]
    local base, total = {}, 0
    for i = 1, count do
        base[i] = skeleton:getLocalRotation(self.chain[i])
        if i < count then
            local ax, ay, az = skeleton:getPosition(self.chain[i])
            local bx, by, bz = skeleton:getPosition(self.chain[i + 1])
            total = total + math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2)
        end
    end
    local lambda = self.damping * total
    local maxStep, columns = math.rad(self.maxStep), {}
    for _ = 1, self.iterations do
        local ex, ey, ez = skeleton:getPosition(tip)
        local dx, dy, dz = tx - ex, ty - ey, tz - ez
        local error = math.sqrt(dx * dx + dy * dy + dz * dz)
        if error <= self.tolerance then
            break
        end
        -- Take a bounded step toward the target so the linearisation stays valid.
        local reach = math.min(error, total * 0.3)
        dx, dy, dz = dx / error * reach, dy / error * reach, dz / error * reach
        local a = { lambda * lambda, 0, 0, lambda * lambda, 0, lambda * lambda }
        local n = 0
        for j = 1, count - 1 do
            local px, py, pz = skeleton:getPosition(self.chain[j])
            local rx, ry, rz = ex - px, ey - py, ez - pz
            for _, axis in ipairs(AXES) do
                n = n + 1
                -- Rotation axis crossed with the lever arm: the tip velocity per radian.
                local c = columns[n] or {}
                columns[n] = c
                c[1] = axis[2] * rz - axis[3] * ry
                c[2] = axis[3] * rx - axis[1] * rz
                c[3] = axis[1] * ry - axis[2] * rx
                a[1] = a[1] + c[1] * c[1]
                a[2] = a[2] + c[1] * c[2]
                a[3] = a[3] + c[1] * c[3]
                a[4] = a[4] + c[2] * c[2]
                a[5] = a[5] + c[2] * c[3]
                a[6] = a[6] + c[3] * c[3]
            end
        end
        local yx, yy, yz = solve3(a, { dx, dy, dz })
        if not yx then
            break
        end
        n = 0
        for j = 1, count - 1 do
            local wx, wy, wz = 0, 0, 0
            for k = 1, 3 do
                n = n + 1
                local c = columns[n]
                local angle = c[1] * yx + c[2] * yy + c[3] * yz
                if k == 1 then
                    wx = angle
                elseif k == 2 then
                    wy = angle
                else
                    wz = angle
                end
            end
            local magnitude = math.sqrt(wx * wx + wy * wy + wz * wz)
            if magnitude > 1e-9 then
                if magnitude > maxStep then
                    magnitude = maxStep
                end
                local name = self.chain[j]
                skeleton:rotate(name, Quat.axisAngle(wx, wy, wz, magnitude))
                if self.limit and self.limit > 0 then
                    skeleton:limitLocal(name, base[j], math.rad(self.limit))
                end
            end
        end
    end
end

return Jacobian
