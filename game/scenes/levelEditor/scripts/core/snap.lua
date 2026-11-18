-- Snap and gizmo drag math. Vectors are plain arrays { x, y, z }; nothing here allocates unless
-- the caller omits an `out` table, and nothing touches the engine.
local Snap = {}

-- Nearest multiple of `step`; a step of 0 or less leaves the value alone.
function Snap.value(value, step)
    if not step or step <= 0 then
        return value
    end
    return math.floor(value / step + 0.5) * step
end

function Snap.vector(v, step, out)
    out = out or {}
    out[1], out[2], out[3] = Snap.value(v[1], step), Snap.value(v[2], step), Snap.value(v[3], step)
    return out
end

-- Degrees snapped to `step` and wrapped into (-180, 180].
function Snap.angle(degrees, step)
    degrees = Snap.value(degrees, step)
    degrees = (degrees + 180) % 360 - 180
    if degrees == -180 then
        degrees = 180
    end
    return degrees
end

-- `invert` is the Ctrl state: it flips whether snapping applies.
function Snap.active(enabled, invert)
    return (enabled and not invert) or (not enabled and invert) or false
end

local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

-- Distance along the axis line (point p, unit direction a) of the point closest to the ray
-- (origin o, direction d). Nil when the ray is parallel to the axis.
function Snap.axisParameter(o, d, p, a)
    local w = { o[1] - p[1], o[2] - p[2], o[3] - p[3] }
    local b = dot(d, a)
    local denominator = 1 - b * b -- d and a are unit length
    if denominator < 1e-6 then
        return nil
    end
    local dw, aw = dot(d, w), dot(a, w)
    return (aw - b * dw) / denominator
end

-- Point where the ray meets the plane (point q, normal n); nil when parallel or behind the ray.
function Snap.planePoint(o, d, q, n, out)
    local denominator = dot(d, n)
    if math.abs(denominator) < 1e-6 then
        return nil
    end
    local t = ((q[1] - o[1]) * n[1] + (q[2] - o[2]) * n[2] + (q[3] - o[3]) * n[3]) / denominator
    if t < 0 then
        return nil
    end
    out = out or {}
    out[1], out[2], out[3] = o[1] + d[1] * t, o[2] + d[2] * t, o[3] + d[3] * t
    return out, t
end

-- Signed angle in degrees from vector u to vector v around the unit axis a (right-handed).
function Snap.angleAround(a, u, v)
    local cx = u[2] * v[3] - u[3] * v[2]
    local cy = u[3] * v[1] - u[1] * v[3]
    local cz = u[1] * v[2] - u[2] * v[1]
    local sine = cx * a[1] + cy * a[2] + cz * a[3]
    return math.deg(math.atan2(sine, dot(u, v)))
end

-- Scale factor for a drag that moved from `start` to `current` along an axis, measured from
-- the pivot at 0. Clamped away from zero so an object never collapses.
function Snap.scaleFactor(start, current)
    if math.abs(start) < 1e-6 then
        return 1
    end
    local factor = current / start
    if math.abs(factor) < 0.01 then
        factor = factor < 0 and -0.01 or 0.01
    end
    return factor
end

return Snap
