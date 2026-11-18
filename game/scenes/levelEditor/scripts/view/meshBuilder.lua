-- Vertex lists for the gizmo parts: bars (a box along a segment), flat plates and rings. Pure
-- Lua. Every face is written with both windings, so the parts show whichever way the renderer
-- culls. Vertex layout is the engine's: x y z u v nx ny nz.
local Builder = {}

local sqrt = math.sqrt

local function unit(x, y, z)
    local length = sqrt(x * x + y * y + z * z)
    if length < 1e-9 then
        return 0, 1, 0
    end
    return x / length, y / length, z / length
end

local function cross(a, b)
    return a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]
end

local function vertex(p, n)
    return { p[1], p[2], p[3], 0, 0, n[1], n[2], n[3] }
end

local function quad(vertices, a, b, c, d, n)
    for _, set in ipairs({ { a, b, c, a, c, d }, { a, c, b, a, d, c } }) do
        for _, p in ipairs(set) do
            vertices[#vertices + 1] = vertex(p, n)
        end
    end
end

-- A box from point `a` to point `b` with a square cross-section of half-width `half`.
-- `hint` is any vector not parallel to the bar; it fixes how the cross-section is turned.
function Builder.bar(vertices, a, b, hint, half)
    local t = { unit(b[1] - a[1], b[2] - a[2], b[3] - a[3]) }
    local ux, uy, uz = cross(t, hint)
    if ux * ux + uy * uy + uz * uz < 1e-9 then
        ux, uy, uz = cross(t, { 1, 0, 0 })
        if ux * ux + uy * uy + uz * uz < 1e-9 then
            ux, uy, uz = cross(t, { 0, 1, 0 })
        end
    end
    local u = { unit(ux, uy, uz) }
    local v = { unit(cross(t, u)) }
    local signs = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
    local function corner(p, sign)
        return {
            p[1] + (u[1] * sign[1] + v[1] * sign[2]) * half,
            p[2] + (u[2] * sign[1] + v[2] * sign[2]) * half,
            p[3] + (u[3] * sign[1] + v[3] * sign[2]) * half,
        }
    end
    for i = 1, 4 do
        local j = i % 4 + 1
        local mid = {
            (u[1] * (signs[i][1] + signs[j][1]) + v[1] * (signs[i][2] + signs[j][2])) / 2,
            (u[2] * (signs[i][1] + signs[j][1]) + v[2] * (signs[i][2] + signs[j][2])) / 2,
            (u[3] * (signs[i][1] + signs[j][1]) + v[3] * (signs[i][2] + signs[j][2])) / 2,
        }
        quad(vertices, corner(a, signs[i]), corner(a, signs[j]), corner(b, signs[j]), corner(b, signs[i]), mid)
    end
    quad(vertices, corner(a, signs[1]), corner(a, signs[2]), corner(a, signs[3]), corner(a, signs[4]), { -t[1], -t[2], -t[3] })
    quad(vertices, corner(b, signs[1]), corner(b, signs[2]), corner(b, signs[3]), corner(b, signs[4]), t)
end

-- A flat square in the plane of two axes: `i` and `j` are axis indices 1..3, spanning
-- [from, to] on both, thickness `thin` along the third axis.
function Builder.plate(vertices, i, j, from, to, thin)
    local k = 6 - i - j
    local function point(a, b, c)
        local p = {}
        p[i], p[j], p[k] = a, b, c
        return p
    end
    local n = { 0, 0, 0 }
    n[k] = 1
    for _, side in ipairs({ thin, -thin }) do
        local sign = side > 0 and 1 or -1
        local normal = { n[1] * sign, n[2] * sign, n[3] * sign }
        quad(vertices, point(from, from, side), point(to, from, side), point(to, to, side), point(from, to, side), normal)
    end
end

-- A ring of bars around axis `axis` (1..3) at `radius`.
function Builder.ring(vertices, axis, radius, half, segments)
    local i, j = axis % 3 + 1, (axis + 1) % 3 + 1
    local function point(angle)
        local p = {}
        p[i], p[j], p[axis] = math.cos(angle) * radius, math.sin(angle) * radius, 0
        return p
    end
    local up = { 0, 0, 0 }
    up[axis] = 1
    for step = 0, segments - 1 do
        local a = point(step / segments * 2 * math.pi)
        local b = point((step + 1) / segments * 2 * math.pi)
        Builder.bar(vertices, a, b, up, half)
    end
end

return Builder
