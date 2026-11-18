-- Hit testing and rotation math of the transform gizmos. Pure Lua: a ray is { o, d } with unit d,
-- `axes` is { {x}, {y}, {z} } of unit vectors (world or local), `length` is the gizmo radius in
-- world units and `tol` the pick tolerance in world units (the caller derives both from the
-- camera so the gizmo keeps a constant size on screen).
local Snap = require('./snap')

local GizmoMath = {}

local sqrt = math.sqrt

local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

-- Closest approach of the ray to the segment a..b: returns distance, parameter along the
-- segment (0..1) and the ray distance. Standard two-line closest points, clamped to the segment.
function GizmoMath.raySegment(o, d, a, b)
    local u = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
    local w = { a[1] - o[1], a[2] - o[2], a[3] - o[3] }
    local uu, ud, dd = dot(u, u), dot(u, d), dot(d, d)
    local uw, dw = dot(u, w), dot(d, w)
    local denominator = uu * dd - ud * ud
    local s, t
    if denominator < 1e-9 then
        s, t = 0, dw / dd
    else
        s = (ud * dw - dd * uw) / denominator
        t = (uu * dw - ud * uw) / denominator
    end
    s = math.max(0, math.min(1, s))
    t = (ud * s + dw) / dd
    if t < 0 then
        t = 0
    end
    local px, py, pz = a[1] + u[1] * s, a[2] + u[2] * s, a[3] + u[3] * s
    local qx, qy, qz = o[1] + d[1] * t, o[2] + d[2] * t, o[3] + d[3] * t
    return sqrt((px - qx) ^ 2 + (py - qy) ^ 2 + (pz - qz) ^ 2), s, t
end

local NAMES = { 'x', 'y', 'z' }
local PLANES = { { 1, 2, 'xy' }, { 2, 3, 'yz' }, { 1, 3, 'xz' } }

local function along(pivot, axis, distance)
    return { pivot[1] + axis[1] * distance, pivot[2] + axis[2] * distance, pivot[3] + axis[3] * distance }
end

-- The handle under the ray for a tool ('Move', 'Rotate', 'Scale'), or nil. Returns the handle
-- name ('x'/'y'/'z', a plane 'xy'/'yz'/'xz' for Move, 'all' for Scale's centre) and its ray
-- distance, so overlapping handles resolve to the nearest one.
function GizmoMath.pick(tool, ray, pivot, axes, length, tol)
    local o, d = ray[1], ray[2]
    local best, bestT, bestScore = nil, nil, math.huge
    local function consider(name, score, t)
        if score < bestScore then
            best, bestT, bestScore = name, t, score
        end
    end
    if tool == 'Move' or tool == 'Scale' then
        for index = 1, 3 do
            local axis = axes[index]
            local distance, _, t =
                GizmoMath.raySegment(o, d, along(pivot, axis, 0.12 * length), along(pivot, axis, length))
            if distance < tol then
                consider(NAMES[index], distance, t)
            end
        end
    end
    if tool == 'Move' then
        for _, plane in ipairs(PLANES) do
            local normal = axes[6 - plane[1] - plane[2]]
            local point, t = Snap.planePoint(o, d, pivot, normal)
            if point then
                local rx, ry, rz = point[1] - pivot[1], point[2] - pivot[2], point[3] - pivot[3]
                local a = (rx * axes[plane[1]][1] + ry * axes[plane[1]][2] + rz * axes[plane[1]][3]) / length
                local b = (rx * axes[plane[2]][1] + ry * axes[plane[2]][2] + rz * axes[plane[2]][3]) / length
                if a > 0.2 and a < 0.5 and b > 0.2 and b < 0.5 then
                    -- Planes lose ties to axes: a small bias keeps arrows grabbable at corners.
                    consider(plane[3], tol * 0.5, t)
                end
            end
        end
    elseif tool == 'Scale' then
        local rx, ry, rz = pivot[1] - o[1], pivot[2] - o[2], pivot[3] - o[3]
        local t = rx * d[1] + ry * d[2] + rz * d[3]
        local cx, cy, cz = o[1] + d[1] * t - pivot[1], o[2] + d[2] * t - pivot[2], o[3] + d[3] * t - pivot[3]
        if sqrt(cx * cx + cy * cy + cz * cz) < 0.14 * length then
            consider('all', -1, t)
        end
    elseif tool == 'Rotate' then
        for index = 1, 3 do
            local point, t = Snap.planePoint(o, d, pivot, axes[index])
            if point then
                local rx, ry, rz = point[1] - pivot[1], point[2] - pivot[2], point[3] - pivot[3]
                local distance = math.abs(sqrt(rx * rx + ry * ry + rz * rz) - length)
                if distance < tol then
                    consider(NAMES[index], distance, t)
                end
            end
        end
    end
    return best, bestT
end

-- 4x4 row-major rotation about a unit axis (Rodrigues), angle in degrees.
function GizmoMath.axisAngle(axis, degrees)
    local x, y, z = axis[1], axis[2], axis[3]
    local c, s = math.cos(math.rad(degrees)), math.sin(math.rad(degrees))
    local k = 1 - c
    return {
        c + x * x * k, x * y * k - z * s, x * z * k + y * s, 0,
        y * x * k + z * s, c + y * y * k, y * z * k - x * s, 0,
        z * x * k - y * s, z * y * k + x * s, c + z * z * k, 0,
        0, 0, 0, 1,
    }
end

local function multiply(a, b)
    local out = {}
    for row = 0, 3 do
        for column = 1, 4 do
            local sum = 0
            for k = 1, 4 do
                sum = sum + a[row * 4 + k] * b[(k - 1) * 4 + column]
            end
            out[row * 4 + column] = sum
        end
    end
    return out
end
GizmoMath.multiply = multiply

-- New Euler rotation after turning a node by `degrees` about `axis` (a world axis, or the
-- node's own axis when `isLocal`). `compose(position, rotation, scale)` and `euler(matrix)` are
-- the engine's own (math3d.compose, Affine.euler), so the rotation order is theirs.
function GizmoMath.rotateEuler(rotation, axis, degrees, isLocal, compose, euler)
    local current = compose({ 0, 0, 0 }, rotation, { 1, 1, 1 })
    local turn = GizmoMath.axisAngle(axis, degrees)
    local result = isLocal and multiply(current, turn) or multiply(turn, current)
    return euler(result)
end

-- Rotates the point p about `pivot` by `degrees` around the world unit axis.
function GizmoMath.rotatePoint(p, pivot, axis, degrees)
    local m = GizmoMath.axisAngle(axis, degrees)
    local x, y, z = p[1] - pivot[1], p[2] - pivot[2], p[3] - pivot[3]
    return {
        pivot[1] + m[1] * x + m[2] * y + m[3] * z,
        pivot[2] + m[5] * x + m[6] * y + m[7] * z,
        pivot[3] + m[9] * x + m[10] * y + m[11] * z,
    }
end

return GizmoMath
