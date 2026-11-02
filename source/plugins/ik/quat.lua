-- Quaternion helpers for {x, y, z, w} arrays (the layout of `node.rotation`). Functions that
-- return a quaternion accept an optional `out` table so solvers can avoid allocations.
local Quat = {}

local EPSILON = 1e-9

function Quat.identity(out)
    out = out or {}
    out[1], out[2], out[3], out[4] = 0, 0, 0, 1
    return out
end

function Quat.copy(q, out)
    out = out or {}
    out[1], out[2], out[3], out[4] = q[1], q[2], q[3], q[4]
    return out
end

function Quat.normalize(q, out)
    out = out or q
    local length = math.sqrt(q[1] ^ 2 + q[2] ^ 2 + q[3] ^ 2 + q[4] ^ 2)
    if length < EPSILON then
        return Quat.identity(out)
    end
    out[1], out[2], out[3], out[4] = q[1] / length, q[2] / length, q[3] / length, q[4] / length
    return out
end

-- Hamilton product a * b: applies b first, then a.
function Quat.multiply(a, b, out)
    out = out or {}
    local ax, ay, az, aw = a[1], a[2], a[3], a[4]
    local bx, by, bz, bw = b[1], b[2], b[3], b[4]
    out[1] = aw * bx + ax * bw + ay * bz - az * by
    out[2] = aw * by - ax * bz + ay * bw + az * bx
    out[3] = aw * bz + ax * by - ay * bx + az * bw
    out[4] = aw * bw - ax * bx - ay * by - az * bz
    return out
end

function Quat.conjugate(q, out)
    out = out or {}
    out[1], out[2], out[3], out[4] = -q[1], -q[2], -q[3], q[4]
    return out
end

function Quat.axisAngle(x, y, z, radians, out)
    out = out or {}
    local length = math.sqrt(x * x + y * y + z * z)
    if length < EPSILON then
        return Quat.identity(out)
    end
    local s = math.sin(radians * 0.5) / length
    out[1], out[2], out[3], out[4] = x * s, y * s, z * s, math.cos(radians * 0.5)
    return out
end

function Quat.rotate(q, x, y, z)
    local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
    -- v + 2 * cross(q.xyz, cross(q.xyz, v) + w * v)
    local cx, cy, cz = qy * z - qz * y + qw * x, qz * x - qx * z + qw * y, qx * y - qy * x + qw * z
    return x + 2 * (qy * cz - qz * cy), y + 2 * (qz * cx - qx * cz), z + 2 * (qx * cy - qy * cx)
end

-- Shortest-arc rotation taking direction a onto direction b. Zero-length inputs give identity.
function Quat.fromTo(ax, ay, az, bx, by, bz, out)
    out = out or {}
    local la, lb = math.sqrt(ax * ax + ay * ay + az * az), math.sqrt(bx * bx + by * by + bz * bz)
    if la < EPSILON or lb < EPSILON then
        return Quat.identity(out)
    end
    ax, ay, az, bx, by, bz = ax / la, ay / la, az / la, bx / lb, by / lb, bz / lb
    local dot = ax * bx + ay * by + az * bz
    if dot < -0.999999 then
        -- Opposite directions: any axis perpendicular to a works.
        local px, py, pz = 0, -az, ay
        if math.abs(ax) < 0.9 then
            px, py, pz = 0, -az, ay
        else
            px, py, pz = az, 0, -ax
        end
        return Quat.axisAngle(px, py, pz, math.pi, out)
    end
    out[1], out[2], out[3], out[4] = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx, 1 + dot
    return Quat.normalize(out)
end

-- Rotation angle in radians (0..pi) of a unit quaternion.
function Quat.angle(q)
    return 2 * math.acos(math.min(1, math.abs(q[4])))
end

function Quat.slerp(a, b, t, out)
    out = out or {}
    local dot = a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
    local sign = dot < 0 and -1 or 1
    dot = math.min(1, math.abs(dot))
    local wa, wb = 1 - t, t
    if dot < 0.9995 then
        local angle = math.acos(dot)
        local s = math.sin(angle)
        wa, wb = math.sin((1 - t) * angle) / s, math.sin(t * angle) / s
    end
    out[1] = a[1] * wa + b[1] * wb * sign
    out[2] = a[2] * wa + b[2] * wb * sign
    out[3] = a[3] * wa + b[3] * wb * sign
    out[4] = a[4] * wa + b[4] * wb * sign
    return Quat.normalize(out)
end

-- Fraction t (0..1) of rotation q, i.e. slerp(identity, q, t).
local IDENTITY = { 0, 0, 0, 1 }
function Quat.scale(q, t, out)
    return Quat.slerp(IDENTITY, q, t, out)
end

-- Rotation of a row-major 4x4 matrix (scale removed). Assumes no shear.
function Quat.fromMatrix(m, out)
    out = out or {}
    local sx = math.sqrt(m[1] ^ 2 + m[5] ^ 2 + m[9] ^ 2)
    local sy = math.sqrt(m[2] ^ 2 + m[6] ^ 2 + m[10] ^ 2)
    local sz = math.sqrt(m[3] ^ 2 + m[7] ^ 2 + m[11] ^ 2)
    sx, sy, sz = math.max(sx, EPSILON), math.max(sy, EPSILON), math.max(sz, EPSILON)
    local r11, r12, r13 = m[1] / sx, m[2] / sy, m[3] / sz
    local r21, r22, r23 = m[5] / sx, m[6] / sy, m[7] / sz
    local r31, r32, r33 = m[9] / sx, m[10] / sy, m[11] / sz
    local trace = r11 + r22 + r33
    if trace > 0 then
        local s = math.sqrt(trace + 1) * 2
        out[4], out[1], out[2], out[3] = 0.25 * s, (r32 - r23) / s, (r13 - r31) / s, (r21 - r12) / s
    elseif r11 > r22 and r11 > r33 then
        local s = math.sqrt(1 + r11 - r22 - r33) * 2
        out[4], out[1], out[2], out[3] = (r32 - r23) / s, 0.25 * s, (r12 + r21) / s, (r13 + r31) / s
    elseif r22 > r33 then
        local s = math.sqrt(1 + r22 - r11 - r33) * 2
        out[4], out[1], out[2], out[3] = (r13 - r31) / s, (r12 + r21) / s, 0.25 * s, (r23 + r32) / s
    else
        local s = math.sqrt(1 + r33 - r11 - r22) * 2
        out[4], out[1], out[2], out[3] = (r21 - r12) / s, (r13 + r31) / s, (r23 + r32) / s, 0.25 * s
    end
    return Quat.normalize(out)
end

return Quat
