-- Car body geometry. The hull and the cabin are lofted from cross-sections (rear to front), so
-- the car has a hood, a sloped windshield and a tapered tail instead of two boxes. Every surface
-- is finely subdivided: the replicated dents push these vertices, so a hit really bends the panel.
-- Vertices follow the engine format {x, y, z, u, v, nx, ny, nz}.
local Geometry = require('source.engine.graphics.geometry.primitives')

local Body = {}

-- { z, half width, bottom y, top y }, rear to front. y is height above the ground plane.
local HULL = {
    { -2.1, 0.86, 0.34, 0.92 },
    { -1.9, 0.9, 0.3, 0.98 },
    { -1.0, 0.92, 0.28, 0.98 },
    { 0.6, 0.92, 0.28, 0.98 },
    { 1.5, 0.9, 0.3, 0.86 },
    { 2.1, 0.82, 0.36, 0.7 },
}
local CABIN = {
    { -1.45, 0.74, 0.98, 1.0 },
    { -0.95, 0.74, 0.98, 1.5 },
    { 0.3, 0.72, 0.98, 1.5 },
    { 0.95, 0.76, 0.98, 1.02 },
}
local STEPS_Z, STEPS_X, STEPS_Y = 3, 4, 3

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- The cross-section at z (linear between the given ones).
local function section(list, z)
    for i = 1, #list - 1 do
        local a, b = list[i], list[i + 1]
        if z <= b[1] + 1e-9 then
            local t = (z - a[1]) / (b[1] - a[1])
            return lerp(a[2], b[2], t), lerp(a[3], b[3], t), lerp(a[4], b[4], t)
        end
    end
    local last = list[#list]
    return last[2], last[3], last[4]
end

-- Adds a quad grid; point(u, v) in 0..1. Triangles are wound to face away from `center`.
local function grid(out, point, countU, countV, center)
    for i = 0, countU - 1 do
        for j = 0, countV - 1 do
            local function at(a, b)
                local x, y, z = point((i + a) / countU, (j + b) / countV)
                return { x, y, z, (i + a) / countU, (j + b) / countV, 0, 1, 0 }
            end
            local p00, p10, p01, p11 = at(0, 0), at(1, 0), at(0, 1), at(1, 1)
            for _, tri in ipairs({ { p00, p10, p11 }, { p00, p11, p01 } }) do
                local a, b, c = tri[1], tri[2], tri[3]
                local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
                local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
                local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                local mx, my, mz =
                    (a[1] + b[1] + c[1]) / 3 - center[1],
                    (a[2] + b[2] + c[2]) / 3 - center[2],
                    (a[3] + b[3] + c[3]) / 3 - center[3]
                if nx * mx + ny * my + nz * mz < 0 then
                    b, c = c, b
                end
                out[#out + 1], out[#out + 2], out[#out + 3] = a, b, c
            end
        end
    end
end

-- Lofts the sections into a closed body. Faces go to `groups`: top, bottom, sides (left/right) and
-- ends (rear/front caps).
local function loft(list, groups, center)
    local first, last = list[1][1], list[#list][1]
    local function at(z)
        return section(list, z)
    end
    local countZ = (#list - 1) * STEPS_Z
    local function z(u)
        return lerp(first, last, u)
    end
    grid(groups.top, function(u, v)
        local hw, _, y1 = at(z(u))
        return lerp(-hw, hw, v), y1, z(u)
    end, countZ, STEPS_X, center)
    grid(groups.bottom, function(u, v)
        local hw, y0 = at(z(u))
        return lerp(-hw, hw, v), y0, z(u)
    end, countZ, STEPS_X, center)
    for _, side in ipairs({ -1, 1 }) do
        grid(groups.sides, function(u, v)
            local hw, y0, y1 = at(z(u))
            return side * hw, lerp(y0, y1, v), z(u)
        end, countZ, STEPS_Y, center)
    end
    for _, end_ in ipairs({ first, last }) do
        grid(groups.ends, function(u, v)
            local hw, y0, y1 = at(end_)
            return lerp(-hw, hw, u), lerp(y0, y1, v), end_
        end, STEPS_X, STEPS_Y, center)
    end
end

local function flatNormals(vertices)
    for index = 1, #vertices, 3 do
        local a, b, c = vertices[index], vertices[index + 1], vertices[index + 2]
        local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
        local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local length = math.sqrt(nx * nx + ny * ny + nz * nz)
        if length > 1e-9 then
            nx, ny, nz = nx / length, ny / length, nz / length
        end
        for k = index, index + 2 do
            vertices[k][6], vertices[k][7], vertices[k][8] = nx, ny, nz
        end
    end
end

local function copyOf(rest)
    local vertices = {}
    for index, vertex in ipairs(rest) do
        vertices[index] = { unpack(vertex) }
    end
    return vertices
end

local function make(rest)
    local vertices = copyOf(rest)
    flatNormals(vertices)
    local radius = 0
    for _, vertex in ipairs(vertices) do
        radius = math.max(radius, math.sqrt(vertex[1] ^ 2 + vertex[2] ^ 2 + vertex[3] ^ 2))
    end
    return {
        mesh = katsa.graphics.newMesh(Geometry.format, vertices, 'triangles', 'dynamic'),
        vertices = vertices,
        radius = radius + 0.5,
        revision = 0,
    }
end

local function append(into, from)
    for _, vertex in ipairs(from) do
        into[#into + 1] = vertex
    end
end

-- Returns two parts, each { geometry, rest }: `paint` (hull and roof) and `glass` (the cabin walls).
function Body.create()
    local hull = { top = {}, bottom = {}, sides = {}, ends = {} }
    loft(HULL, hull, { 0, 0.6, 0 })
    local cabin = { top = {}, bottom = {}, sides = {}, ends = {} }
    loft(CABIN, cabin, { 0, 1.2, -0.25 })
    local paint, glass = {}, {}
    for _, name in ipairs({ 'top', 'bottom', 'sides', 'ends' }) do
        append(paint, hull[name])
    end
    append(paint, cabin.top)
    append(glass, cabin.sides)
    append(glass, cabin.ends)
    return { geometry = make(paint), rest = paint },
        { geometry = make(glass), rest = glass }
end

-- Re-applies the dents of `deformation` to the rest pose and uploads the result.
function Body.deform(geometry, rest, deformation)
    for index, base in ipairs(rest) do
        local ox, oy, oz = deformation:offsetAt(base[1], base[2], base[3])
        local vertex = geometry.vertices[index]
        vertex[1], vertex[2], vertex[3] = base[1] + ox, base[2] + oy, base[3] + oz
    end
    flatNormals(geometry.vertices)
    geometry.mesh:setVertices(geometry.vertices)
    geometry.revision = geometry.revision + 1
end

-- A cylinder around the X axis (a tire) as plain vertices.
local function cylinder(radius, width, segments)
    local out = {}
    local function ring(i)
        local a = i / segments * math.pi * 2
        return math.cos(a) * radius, math.sin(a) * radius
    end
    local half = width / 2
    for i = 0, segments - 1 do
        local y0, z0 = ring(i)
        local y1, z1 = ring(i + 1)
        local function v(x, y, z, nx, ny, nz)
            return { x, y, z, 0, 0, nx, ny, nz }
        end
        local ny0, nz0 = y0 / radius, z0 / radius
        local ny1, nz1 = y1 / radius, z1 / radius
        -- Tread.
        out[#out + 1], out[#out + 2], out[#out + 3] =
            v(-half, y0, z0, 0, ny0, nz0), v(half, y1, z1, 0, ny1, nz1), v(half, y0, z0, 0, ny0, nz0)
        out[#out + 1], out[#out + 2], out[#out + 3] =
            v(-half, y0, z0, 0, ny0, nz0), v(-half, y1, z1, 0, ny1, nz1), v(half, y1, z1, 0, ny1, nz1)
        -- Sidewalls.
        out[#out + 1], out[#out + 2], out[#out + 3] =
            v(half, 0, 0, 1, 0, 0), v(half, y0, z0, 1, 0, 0), v(half, y1, z1, 1, 0, 0)
        out[#out + 1], out[#out + 2], out[#out + 3] =
            v(-half, 0, 0, -1, 0, 0), v(-half, y1, z1, -1, 0, 0), v(-half, y0, z0, -1, 0, 0)
    end
    return out
end

-- A five-spoke rim in the YZ plane at both sides of the wheel, so a spinning wheel is visible.
local function rim(radius, width)
    local out = {}
    local half = width / 2 + 0.01
    local spokes, thickness = 5, 0.045
    local function quad(a, b, c, d, normal)
        for _, tri in ipairs({ { a, b, c }, { a, c, d } }) do
            for _, p in ipairs(tri) do
                out[#out + 1] = { p[1], p[2], p[3], 0, 0, normal[1], normal[2], normal[3] }
            end
        end
    end
    for _, side in ipairs({ -1, 1 }) do
        local x = side * half
        for s = 0, spokes - 1 do
            local angle = s / spokes * math.pi * 2
            local c, sn = math.cos(angle), math.sin(angle)
            -- Spoke: a thin strip from the hub to the rim edge.
            local function point(along, across)
                return { x, c * along - sn * across, sn * along + c * across }
            end
            local a, b = point(0, -thickness), point(0, thickness)
            local d, e = point(radius * 0.85, thickness), point(radius * 0.85, -thickness)
            if side > 0 then
                quad(a, b, d, e, { 1, 0, 0 })
            else
                quad(a, e, d, b, { -1, 0, 0 })
            end
        end
    end
    return out
end

function Body.wheelGeometry(radius, width)
    return Geometry.mesh(cylinder(radius, width, 20)), Geometry.mesh(rim(radius, width))
end

return Body
