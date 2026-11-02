local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local M = require('../../math.math3d')

local G = {
    format = {
        { 'VertexPosition', 'float', 3 },
        { 'VertexTexCoord', 'float', 2 },
        {
            'vertexNormal',
            'float',
            3,
        },
    },
}
G.skinFormat = { unpack(G.format) }
G.skinFormat[#G.skinFormat + 1] = { 'skinJoints', 'float', 4 }
G.skinFormat[#G.skinFormat + 1] = { 'skinWeights', 'float', 4 }
G.skinEightFormat = { unpack(G.skinFormat) }
-- Skinned meshes are never instanced. Reuse their unused instance inputs so
-- custom materials stay within the 16-attribute limit on integrated GPUs.
G.skinEightFormat[#G.skinEightFormat + 1] = { 'instanceRow1', 'float', 4 }
G.skinEightFormat[#G.skinEightFormat + 1] = { 'instanceRow2', 'float', 4 }

function G.mesh(vertices, skinned)
    local eightWeights = skinned and vertices[1] and #vertices[1] == 24
    local radius = 0
    for _, v in ipairs(vertices) do
        radius = math.max(radius, math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2))
    end
    return {
        mesh = katsa.graphics.newMesh(
            eightWeights and G.skinEightFormat or (skinned and G.skinFormat or G.format),
            vertices,
            'triangles',
            'static'
        ),
        vertices = vertices,
        radius = radius,
        eightWeights = eightWeights or false,
    }
end

function G.normals(v)
    for i = 1, #v, 3 do
        local a, b, c = v[i], v[i + 1], v[i + 2]
        local x, y, z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
        local u, w, t = c[1] - a[1], c[2] - a[2], c[3] - a[3]
        local nx, ny, nz = M.normalize(y * t - z * w, z * u - x * t, x * w - y * u)
        for j = i, i + 2 do
            if not v[j][6] then
                v[j][6], v[j][7], v[j][8] = nx, ny, nz
            end
        end
    end
    return v
end

function G.cube()
    local p = {
        { -0.5, -0.5, -0.5 },
        { 0.5, -0.5, -0.5 },
        { -0.5, 0.5, -0.5 },
        { 0.5, 0.5, -0.5 },
        { -0.5, -0.5, 0.5 },
        { 0.5, -0.5, 0.5 },
        { -0.5, 0.5, 0.5 },
        { 0.5, 0.5, 0.5 },
    }
    local faces = {
        { 1, 3, 2, 0, 1, 0, 0, 1, 1 },
        { 2, 3, 4, 1, 1, 0, 0, 1, 0 },
        { 5, 6, 7, 0, 1, 1, 1, 0, 0 },
        { 6, 8, 7, 1, 1, 1, 0, 0, 0 },
        { 1, 5, 3, 0, 1, 1, 1, 0, 0 },
        { 5, 7, 3, 1, 1, 1, 0, 0, 0 },
        { 2, 4, 6, 0, 1, 0, 0, 1, 1 },
        { 4, 8, 6, 0, 0, 1, 0, 1, 1 },
        { 1, 2, 5, 0, 1, 1, 1, 0, 0 },
        { 2, 6, 5, 1, 1, 1, 0, 0, 0 },
        { 3, 7, 4, 0, 1, 0, 0, 1, 1 },
        { 4, 7, 8, 1, 1, 0, 0, 1, 0 },
    }
    local v = {}
    for _, f in ipairs(faces) do
        for i = 1, 3 do
            local q = p[f[i]]
            v[#v + 1] = { q[1], q[2], q[3], f[2 * i + 2], f[2 * i + 3] }
        end
    end
    return G.mesh(G.normals(v))
end

function G.plane()
    return G.mesh({
        { -0.5, 0, -0.5, 0, 1, 0, 1, 0 },
        { -0.5, 0, 0.5, 0, 0, 0, 1, 0 },
        { 0.5, 0, -0.5, 1, 1, 0, 1, 0 },
        { 0.5, 0, -0.5, 1, 1, 0, 1, 0 },
        { -0.5, 0, 0.5, 0, 0, 0, 1, 0 },
        { 0.5, 0, 0.5, 1, 0, 0, 1, 0 },
    })
end

function G.quad()
    return G.mesh({
        { -0.5, 0.5, 0, 0, 0, 0, 0, -1 },
        { -0.5, -0.5, 0, 0, 1, 0, 0, -1 },
        { 0.5, 0.5, 0, 1, 0, 0, 0, -1 },
        { 0.5, 0.5, 0, 1, 0, 0, 0, -1 },
        { -0.5, -0.5, 0, 0, 1, 0, 0, -1 },
        { 0.5, -0.5, 0, 1, 1, 0, 0, -1 },
    })
end

function G.rounded(kind, segments, rings)
    segments, rings = segments or 16, rings or 12
    local vertices = {}

    local function vertex(i, j)
        local angle = 2 * math.pi * i / segments
        local latitude = math.pi * (j / rings - 0.5)
        local nx, ny, nz =
            math.cos(latitude) * math.cos(angle),
            math.sin(latitude),
            math.cos(latitude) * math.sin(angle)
        local offset = kind == 'capsule' and (ny >= 0 and 0.5 or -0.5) or 0
        return { nx * 0.5, ny * 0.5 + offset, nz * 0.5, i / segments, 1 - j / rings, nx, ny, nz }
    end

    local function triangle(a, b, c)
        local nx = (b[2] - a[2]) * (c[3] - a[3]) - (b[3] - a[3]) * (c[2] - a[2])
        local ny = (b[3] - a[3]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[3] - a[3])
        local nz = (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
        if nx * a[6] + ny * a[7] + nz * a[8] < 0 then
            b, c = c, b
        end
        vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = a, b, c
    end
    for j = 0, rings - 1 do
        for i = 0, segments - 1 do
            local a, b, c, d =
                vertex(i, j), vertex(i + 1, j), vertex(i, j + 1), vertex(i + 1, j + 1)
            triangle(a, b, c)
            triangle(b, d, c)
        end
    end
    return G.mesh(vertices)
end

function G.sphere()
    return G.rounded('sphere')
end

function G.capsule()
    return G.rounded('capsule', 16, 12)
end

return G
