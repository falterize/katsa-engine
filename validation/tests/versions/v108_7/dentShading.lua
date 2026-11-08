-- A dent keeps each polygon's authored shading: smooth polygons stay smooth, flat ones stay flat.
local Module = {}

local function vertex(x, y, z, nx, ny, nz)
    return { x, y, z, 0, 0, nx, ny, nz }
end

function Module.run(self)
    local CarModel = require('source.game.scenes.multiplayerCars.scripts.view.carModel')
    local Deformation = require('source.game.scenes.multiplayerCars.nodes.vehicle.deformation')
    local rest = {}
    -- Triangle 1: smooth (vertex normals lean away from the face normal +z).
    local s = 0.4
    local l = math.sqrt(1 + s * s)
    rest[1] = vertex(0, 0, 0, -s / l, 0, 1 / l)
    rest[2] = vertex(1, 0, 0, s / l, 0, 1 / l)
    rest[3] = vertex(0, 1, 0, 0, s / l, 1 / l)
    -- Triangle 2: flat (vertex normals equal the face normal), next to the dent as well.
    rest[4] = vertex(0.1, 0, 0, 0, 0, 1)
    rest[5] = vertex(1.1, 0, 0, 0, 0, 1)
    rest[6] = vertex(0.1, 1, 0, 0, 0, 1)
    -- Triangle 3: smooth, shares two corners (position and normal) with triangle 1, bent away.
    rest[7] = vertex(1, 0, 0, s / l, 0, 1 / l)
    rest[8] = vertex(1, 1, -0.5, 0, 0, 1)
    rest[9] = vertex(0, 1, 0, 0, s / l, 1 / l)
    local smooth, group, count = CarModel.analyseShading(rest)
    self:check(smooth[1] == true and smooth[2] == false, 'Authored smooth and flat polygons are told apart')
    self:check(count == 4 and group[2] == group[7] and group[4] == nil, 'Smooth polygons get smoothing groups, flat ones none')

    local vertices = {}
    for i, v in ipairs(rest) do
        vertices[i] = { unpack(v) }
    end
    local part = {
        rest = rest,
        box = { -1, -1, -1, 2, 2, 1 },
        smooth = smooth,
        group = group,
        groups = count,
        geometry = {
            vertices = vertices,
            revision = 0,
            mesh = { setVertices = function() end },
        },
    }
    local dents = Deformation.new()
    dents:add({ x = 0.5, y = 0.3, z = 0.2, dx = 0, dz = -1, dy = 0, depth = 0.3, radius = 1.5 })
    CarModel.deform({ part }, dents)
    local function unit(v)
        return math.abs(v[6] ^ 2 + v[7] ^ 2 + v[8] ^ 2 - 1) < 1e-4
    end
    local flat = vertices[4]
    local a, b = vertices[4], vertices[5]
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local c = vertices[6]
    local wx, wy, wz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
    local n = math.sqrt(nx * nx + ny * ny + nz * nz)
    local same = math.abs((nx * flat[6] + ny * flat[7] + nz * flat[8]) / n) > 0.999
    self:check(same, 'A flat polygon is re-shaded with its own face normal after a dent')
    local differ = false
    for i = 1, 3 do
        local v = vertices[i]
        differ = differ or math.abs(v[6] - rest[i][6]) > 1e-3 or math.abs(v[8] - rest[i][8]) > 1e-3
        self:check(unit(v), 'Dented smooth vertex ' .. i .. ' keeps a unit normal')
    end
    self:check(differ, 'Smooth polygon normals follow the bent surface')
    local p, q = vertices[2], vertices[7]
    self:check(
        math.abs(p[6] - q[6]) < 1e-6 and math.abs(p[8] - q[8]) < 1e-6 and math.abs(p[7] - q[7]) < 1e-6,
        'A corner shared by smooth polygons gets one blended normal'
    )

    -- Repeated hits at one spot never push a point farther than the displacement limit.
    local stacked = Deformation.new({ maxDents = 40 })
    for _ = 1, 30 do
        stacked:add({ x = 0, y = 0.5, z = 2, dx = 0, dz = -1, dy = 0, depth = 0.7, radius = 1.5 })
    end
    local ox, oy, oz = stacked:offsetAt(0, 0.5, 2)
    self:check(math.sqrt(ox * ox + oy * oy + oz * oz) <= 1.0001, 'Stacked dents saturate instead of drifting away')
    local single = Deformation.new()
    single:add({ x = 0, y = 0.5, z = 2, dx = 0, dz = -1, dy = 0, depth = 0.3, radius = 1.5 })
    local sx, _, sz = single:offsetAt(0.4, 0.5, 2)
    self:check(math.abs(sz) > 0.05 and math.abs(sx) < 0.6, 'A single moderate dent is not limited')

    -- Copy-on-write: an undented part draws the shared asset geometry; a dent gives it its own
    -- copy (the shared one is never written); a repair returns it to the shared geometry.
    local shared = { vertices = rest, revision = 0, mesh = { setVertices = function() error('shared mesh written') end } }
    local object = { geometry = shared }
    local cow = {
        rest = rest, box = { -1, -1, -1, 2, 2, 1 }, radius = 2, smooth = smooth, group = group,
        groups = count, shared = shared, geometry = shared, object = object,
    }
    local before = rest[1][3]
    CarModel.deform({ cow }, dents)
    self:check(object.geometry ~= shared and object.geometry == cow.geometry and rest[1][3] == before,
        'A dent gives the part its own geometry and leaves the shared one untouched')
    CarModel.deform({ cow }, Deformation.new())
    self:check(object.geometry == shared and cow.deformed == false, 'A repaired part draws the shared geometry again')
end

return Module
