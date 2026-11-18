-- Cylinder and cone triangle lists (unit size: radius 0.5, height 1, centred on the origin) for
-- the shapes the engine has no `kind` for. `vertices` is pure Lua; `geometry` wraps it in an
-- engine mesh once per shape. Counter-clockwise from outside, like the engine's own primitives.
local Shapes = {}

local SEGMENTS = 24
local R, H = 0.5, 0.5

local function vertex(x, y, z, u, v, nx, ny, nz)
    return { x, y, z, u, v, nx, ny, nz }
end

local function normalize(x, y, z)
    local length = math.sqrt(x * x + y * y + z * z)
    return x / length, y / length, z / length
end

local function build(cone)
    local out = {}
    for i = 0, SEGMENTS - 1 do
        local a0, a1 = i / SEGMENTS * 2 * math.pi, (i + 1) / SEGMENTS * 2 * math.pi
        local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
        local u0, u1 = i / SEGMENTS, (i + 1) / SEGMENTS
        local n0x, n0y, n0z, n1x, n1y, n1z
        if cone then
            n0x, n0y, n0z = normalize(c0, R, s0)
            n1x, n1y, n1z = normalize(c1, R, s1)
        else
            n0x, n0y, n0z, n1x, n1y, n1z = c0, 0, s0, c1, 0, s1
        end
        local b0 = vertex(R * c0, -H, R * s0, u0, 0, n0x, n0y, n0z)
        local b1 = vertex(R * c1, -H, R * s1, u1, 0, n1x, n1y, n1z)
        if cone then
            local mx, my, mz = normalize(math.cos((a0 + a1) / 2), R, math.sin((a0 + a1) / 2))
            local apex = vertex(0, H, 0, (u0 + u1) / 2, 1, mx, my, mz)
            out[#out + 1], out[#out + 2], out[#out + 3] = b0, apex, b1
        else
            local t0 = vertex(R * c0, H, R * s0, u0, 1, n0x, n0y, n0z)
            local t1 = vertex(R * c1, H, R * s1, u1, 1, n1x, n1y, n1z)
            out[#out + 1], out[#out + 2], out[#out + 3] = b0, t1, b1
            out[#out + 1], out[#out + 2], out[#out + 3] = b0, t0, t1
            local top = vertex(0, H, 0, 0.5, 0.5, 0, 1, 0)
            out[#out + 1], out[#out + 2], out[#out + 3] = top,
                vertex(R * c1, H, R * s1, 0.5 + c1 / 2, 0.5 + s1 / 2, 0, 1, 0),
                vertex(R * c0, H, R * s0, 0.5 + c0 / 2, 0.5 + s0 / 2, 0, 1, 0)
        end
        local bottom = vertex(0, -H, 0, 0.5, 0.5, 0, -1, 0)
        out[#out + 1], out[#out + 2], out[#out + 3] = bottom,
            vertex(R * c0, -H, R * s0, 0.5 + c0 / 2, 0.5 + s0 / 2, 0, -1, 0),
            vertex(R * c1, -H, R * s1, 0.5 + c1 / 2, 0.5 + s1 / 2, 0, -1, 0)
    end
    return out
end

Shapes.NAMES = { 'cylinder', 'cone' }

-- A fresh vertex list: { x, y, z, u, v, nx, ny, nz } per vertex, three per triangle.
function Shapes.vertices(name)
    assert(name == 'cylinder' or name == 'cone', 'Unknown editor shape: ' .. tostring(name))
    return build(name == 'cone')
end

local cache = setmetatable({}, { __mode = 'k' })

-- The engine mesh for a shape, shared by every node of that shape in one World3D.
function Shapes.geometry(world, name)
    local Geometry = require('source.engine.graphics.geometry.primitives')
    cache[world] = cache[world] or {}
    local entry = cache[world][name]
    if not entry then
        entry = Geometry.mesh(Shapes.vertices(name))
        world.resources:own(entry.mesh)
        cache[world][name] = entry
    end
    return entry
end

return Shapes
