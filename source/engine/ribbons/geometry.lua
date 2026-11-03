-- Pure ribbon geometry shared by Beam3D and Trail3D (no GL, no nodes).
--
-- A ribbon is a list of centre-line points. Each point is a table the caller owns and reuses:
--   x, y, z       centre position (world space)
--   width         full width at this point
--   r, g, b, a    colour and opacity (a = 1 - transparency)
--   distance      arc length from the first point (drives Stretch / Wrap texture coordinates)
--   fixed         optional: use (sx, sy, sz) as the side direction instead of deriving one
-- `strip` turns the first `n` points into a triangle list in the particle vertex layout
-- { x, y, z, u, v, r, g, b, a }, six vertices per segment.
local sqrt = math.sqrt

local Geometry = {}

local M = require('../math.math3d')
local cross, normalize = M.cross, M.unit

-- Any unit vector perpendicular to the (unit) direction.
local function perpendicular(tx, ty, tz)
    local sx, sy, sz, length = normalize(cross(tx, ty, tz, 0, 1, 0))
    if length == 0 then
        sx, sy, sz = normalize(cross(tx, ty, tz, 1, 0, 0))
    end
    return sx, sy, sz
end

-- Cubic Bezier from p0 to p1 with control points c0 / c1. Fills points[1..segments + 1] with
-- position, `distance` and `t` (0..1 along the curve); width is interpolated from width0 to width1.
function Geometry.curve(points, p0, c0, c1, p1, segments, width0, width1)
    local previous
    local distance = 0
    for i = 0, segments do
        local t = i / segments
        local s = 1 - t
        local w0, w1, w2, w3 = s * s * s, 3 * s * s * t, 3 * s * t * t, t * t * t
        local point = points[i + 1] or {}
        points[i + 1] = point
        point.x = w0 * p0[1] + w1 * c0[1] + w2 * c1[1] + w3 * p1[1]
        point.y = w0 * p0[2] + w1 * c0[2] + w2 * c1[2] + w3 * p1[2]
        point.z = w0 * p0[3] + w1 * c0[3] + w2 * c1[3] + w3 * p1[3]
        if previous then
            local dx, dy, dz = point.x - previous.x, point.y - previous.y, point.z - previous.z
            distance = distance + sqrt(dx * dx + dy * dy + dz * dz)
        end
        point.distance, point.t = distance, t
        point.width = width0 + (width1 - width0) * t
        point.fixed = false
        previous = point
    end
    for i = #points, segments + 2, -1 do
        points[i] = nil
    end
    return distance
end

-- Centre and radius of the first `n` points (width included) for culling.
function Geometry.bounds(points, n)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local pad = 0
    for i = 1, n do
        local p = points[i]
        minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
        minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
        minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
        pad = math.max(pad, p.width)
    end
    local cx, cy, cz = (minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5
    local dx, dy, dz = maxX - minX, maxY - minY, maxZ - minZ
    return cx, cy, cz, sqrt(dx * dx + dy * dy + dz * dz) * 0.5 + pad * 0.5
end

local function put(vertices, count, x, y, z, u, v, p)
    count = count + 1
    local vertex = vertices[count] or {}
    vertices[count] = vertex
    vertex[1], vertex[2], vertex[3], vertex[4], vertex[5] = x, y, z, u, v
    vertex[6], vertex[7], vertex[8], vertex[9] = p.r, p.g, p.b, p.a
    return count
end

-- options:
--   faceCamera    true: the width axis is perpendicular to the view ray (camera = {x, y, z})
--   camera        camera position, used when faceCamera is true
--   normal        {x, y, z} ribbon face normal when faceCamera is false
--   u0, v0, uw, vh  texture region (Image.uv); u runs along the ribbon, v across it
--   uOffset, uScale  u = uOffset + point.distance * uScale   (overridden by point.u when set)
-- Returns the number of vertices written; extra vertices in `vertices` are trimmed.
function Geometry.strip(points, n, options, vertices)
    local count = 0
    if n >= 2 then
        local camera, normal = options.camera, options.normal
        local psx, psy, psz
        for i = 1, n do
            local p = points[i]
            local a, b = points[i > 1 and i - 1 or i], points[i < n and i + 1 or i]
            local tx, ty, tz = normalize(b.x - a.x, b.y - a.y, b.z - a.z)
            local sx, sy, sz, length
            if p.fixed then
                sx, sy, sz, length = normalize(p.sx, p.sy, p.sz)
            elseif options.faceCamera then
                sx, sy, sz, length =
                    normalize(cross(tx, ty, tz, p.x - camera[1], p.y - camera[2], p.z - camera[3]))
            else
                sx, sy, sz, length = normalize(cross(tx, ty, tz, normal[1], normal[2], normal[3]))
            end
            if length == 0 then
                if psx then
                    sx, sy, sz = psx, psy, psz
                else
                    sx, sy, sz = perpendicular(tx, ty, tz)
                end
            elseif psx and sx * psx + sy * psy + sz * psz < 0 then
                -- Keep the ribbon from twisting when the side direction flips sign.
                sx, sy, sz = -sx, -sy, -sz
            end
            psx, psy, psz = sx, sy, sz
            local half = p.width * 0.5
            p.ax, p.ay, p.az = p.x + sx * half, p.y + sy * half, p.z + sz * half
            p.bx, p.by, p.bz = p.x - sx * half, p.y - sy * half, p.z - sz * half
        end
        local u0, v0, uw, vh = options.u0, options.v0, options.uw, options.vh
        local uOffset, uScale = options.uOffset, options.uScale
        for i = 1, n - 1 do
            local p, q = points[i], points[i + 1]
            local up = u0 + (p.u or (uOffset + p.distance * uScale)) * uw
            local uq = u0 + (q.u or (uOffset + q.distance * uScale)) * uw
            local vTop, vBottom = v0, v0 + vh
            count = put(vertices, count, p.ax, p.ay, p.az, up, vTop, p)
            count = put(vertices, count, p.bx, p.by, p.bz, up, vBottom, p)
            count = put(vertices, count, q.ax, q.ay, q.az, uq, vTop, q)
            count = put(vertices, count, p.bx, p.by, p.bz, up, vBottom, p)
            count = put(vertices, count, q.bx, q.by, q.bz, uq, vBottom, q)
            count = put(vertices, count, q.ax, q.ay, q.az, uq, vTop, q)
        end
    end
    for i = #vertices, count + 1, -1 do
        vertices[i] = nil
    end
    return count
end

return Geometry
