-- Car body geometry: two subdivided boxes (hull and cabin) whose vertices can be pushed by the
-- replicated dents. Vertices follow the engine format {x, y, z, u, v, nx, ny, nz}.
local Geometry = require('source.engine.graphics.geometry.primitives')

local Body = {}

local SEGMENTS = 6

-- Appends the six faces of a box centered on (cx, cz) with its base at `baseY`.
local function addBox(list, cx, baseY, cz, width, height, length)
    local function face(origin, u, v, count)
        for i = 0, count - 1 do
            for j = 0, count - 1 do
                local function point(a, b)
                    return {
                        origin[1] + u[1] * (i + a) / count + v[1] * (j + b) / count,
                        origin[2] + u[2] * (i + a) / count + v[2] * (j + b) / count,
                        origin[3] + u[3] * (i + a) / count + v[3] * (j + b) / count,
                        (i + a) / count,
                        (j + b) / count,
                        0,
                        1,
                        0,
                    }
                end
                local p00, p10, p01, p11 = point(0, 0), point(1, 0), point(0, 1), point(1, 1)
                list[#list + 1], list[#list + 2], list[#list + 3] = p00, p10, p11
                list[#list + 1], list[#list + 2], list[#list + 3] = p00, p11, p01
            end
        end
    end
    local x0, x1 = cx - width / 2, cx + width / 2
    local y0, y1 = baseY, baseY + height
    local z0, z1 = cz - length / 2, cz + length / 2
    face({ x0, y0, z1 }, { width, 0, 0 }, { 0, height, 0 }, SEGMENTS) -- front (+z)
    face({ x1, y0, z0 }, { -width, 0, 0 }, { 0, height, 0 }, SEGMENTS) -- back
    face({ x0, y0, z0 }, { 0, 0, length }, { 0, height, 0 }, SEGMENTS) -- left
    face({ x1, y0, z1 }, { 0, 0, -length }, { 0, height, 0 }, SEGMENTS) -- right
    face({ x0, y1, z1 }, { width, 0, 0 }, { 0, 0, -length }, SEGMENTS) -- top
    face({ x0, y0, z0 }, { width, 0, 0 }, { 0, 0, length }, SEGMENTS) -- bottom
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

-- Returns a geometry for Mesh3D plus the rest-pose vertices needed to re-apply dents.
function Body.create()
    local rest = {}
    addBox(rest, 0, 0.25, 0, 1.8, 0.65, 4.2)
    addBox(rest, 0, 0.9, -0.2, 1.5, 0.55, 2.1)
    local vertices = {}
    for index, vertex in ipairs(rest) do
        vertices[index] = { unpack(vertex) }
    end
    flatNormals(vertices)
    local radius = 0
    for _, vertex in ipairs(vertices) do
        radius = math.max(radius, math.sqrt(vertex[1] ^ 2 + vertex[2] ^ 2 + vertex[3] ^ 2))
    end
    local geometry = {
        mesh = katsa.graphics.newMesh(Geometry.format, vertices, 'triangles', 'dynamic'),
        vertices = vertices,
        radius = radius + 0.5,
        revision = 0,
    }
    return geometry, rest
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

return Body
