local M = {}
function M.identity()
    return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end
function M.multiply(a, b, out)
    out = out or {}
    -- Cache the right operand once. Row-local reads also make both output aliases safe.
    local b1, b2, b3, b4 = b[1], b[2], b[3], b[4]
    local b5, b6, b7, b8 = b[5], b[6], b[7], b[8]
    local b9, b10, b11, b12 = b[9], b[10], b[11], b[12]
    local b13, b14, b15, b16 = b[13], b[14], b[15], b[16]
    for i = 0, 12, 4 do
        local x, y, z, w = a[i + 1], a[i + 2], a[i + 3], a[i + 4]
        out[i + 1] = x * b1 + y * b5 + z * b9 + w * b13
        out[i + 2] = x * b2 + y * b6 + z * b10 + w * b14
        out[i + 3] = x * b3 + y * b7 + z * b11 + w * b15
        out[i + 4] = x * b4 + y * b8 + z * b12 + w * b16
    end
    return out
end
function M.transform(m, x, y, z, w)
    w = w or 1
    return m[1] * x + m[2] * y + m[3] * z + m[4] * w,
        m[5] * x + m[6] * y + m[7] * z + m[8] * w,
        m[9] * x + m[10] * y + m[11] * z + m[12] * w
end
function M.normalize(x, y, z)
    local n = math.sqrt(x * x + y * y + z * z)
    if n < 1e-12 then
        return 0, 1, 0
    end
    return x / n, y / n, z / n
end
function M.distanceSquared(a, b)
    return (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2
end
-- Source convention: degrees, X then negative Y then Z, positive Z forward.
function M.compose(p, r, s, out)
    out = out or {}
    local x, y, z = math.rad(r[1]), math.rad(r[2]), math.rad(r[3])
    local cx, sx, cy, sy, cz, sz =
        math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    out[1] = cz * cy * s[1]
    out[2] = (-cz * sy * sx - sz * cx) * s[2]
    out[3] = (-cz * sy * cx + sz * sx) * s[3]
    out[4] = p[1]
    out[5] = sz * cy * s[1]
    out[6] = (-sz * sy * sx + cz * cx) * s[2]
    out[7] = (-sz * sy * cx - cz * sx) * s[3]
    out[8] = p[2]
    out[9] = sy * s[1]
    out[10] = cy * sx * s[2]
    out[11] = cy * cx * s[3]
    out[12] = p[3]
    out[13], out[14], out[15], out[16] = 0, 0, 0, 1
    return out
end
function M.trs(p, q, s, out)
    out = out or {}
    local x, y, z, w = q[1], q[2], q[3], q[4]
    out[1], out[2], out[3], out[4] =
        (1 - 2 * y * y - 2 * z * z) * s[1],
        (2 * x * y - 2 * z * w) * s[2],
        (2 * x * z + 2 * y * w) * s[3],
        p[1]
    out[5], out[6], out[7], out[8] =
        (2 * x * y + 2 * z * w) * s[1],
        (1 - 2 * x * x - 2 * z * z) * s[2],
        (2 * y * z - 2 * x * w) * s[3],
        p[2]
    out[9], out[10], out[11], out[12] =
        (2 * x * z - 2 * y * w) * s[1],
        (2 * y * z + 2 * x * w) * s[2],
        (1 - 2 * x * x - 2 * y * y) * s[3],
        p[3]
    out[13], out[14], out[15], out[16] = 0, 0, 0, 1
    return out
end
function M.normalMatrix(m, out)
    out = out or {}
    local a, b, c, d, e, f, g, h, i = m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11]
    local det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    if math.abs(det) < 1e-12 then
        det = 1
    end
    out[1] = (e * i - f * h) / det
    out[2] = (f * g - d * i) / det
    out[3] = (d * h - e * g) / det
    out[4] = (c * h - b * i) / det
    out[5] = (a * i - c * g) / det
    out[6] = (b * g - a * h) / det
    out[7] = (b * f - c * e) / det
    out[8] = (c * d - a * f) / det
    out[9] = (a * e - b * d) / det
    return out
end
function M.rayTriangle(ox, oy, oz, dx, dy, dz, a, b, c)
    local ex, ey, ez = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local fx, fy, fz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local px, py, pz = dy * fz - dz * fy, dz * fx - dx * fz, dx * fy - dy * fx
    local det = ex * px + ey * py + ez * pz
    if math.abs(det) < 1e-9 then
        return
    end
    local tx, ty, tz = ox - a[1], oy - a[2], oz - a[3]
    local u = (tx * px + ty * py + tz * pz) / det
    if u < 0 or u > 1 then
        return
    end
    local qx, qy, qz = ty * ez - tz * ey, tz * ex - tx * ez, tx * ey - ty * ex
    local v = (dx * qx + dy * qy + dz * qz) / det
    if v < 0 or u + v > 1 then
        return
    end
    local t = (fx * qx + fy * qy + fz * qz) / det
    if t > 0 then
        return t
    end
end
return M
