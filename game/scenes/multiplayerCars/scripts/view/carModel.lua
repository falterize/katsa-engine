-- The visible Duke 69: the converted GLB (assets/models/duke69.glb, built by
-- tools/import/fbxCarToGlb.py) turned into scene nodes. The file is in car space (faces +z,
-- +x right, origin on the ground below the chassis centre), so no node needs a transform.
--
--   * Body, Hood and Trunkdoor are the paint: tinted per car, no texture.
--   * Wheel_FL/FR/RL/RR are pivots at the hub with a hub-centred mesh, so the view can spin and
--     steer them and a lost wheel keeps its own geometry.
--   * Parts that bend in a crash share the asset's geometry until the first dent reaches them;
--     then the part gets its own copy (copy-on-write) and returns to the shared geometry once
--     it is repaired. Undented cars therefore draw as instances of one mesh per part and cost no
--     vertex memory of their own. The interior, steering wheel and suspension never bend.
local Models = require('source.engine.import.models')
local Geometry = require('source.engine.graphics.geometry.primitives')

local CarModel = {}

CarModel.PATH = 'scene://models/duke69.glb'
CarModel.WHEEL_ORDER = { 'Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR' } -- model.wheels order

local PAINT = { Body = true, Hood = true, Trunkdoor = true }
local RIGID = { Interior = true, Steering_Wheel = true, Suspension = true }

-- Copies a vertex list. The fields are spelled out: `{ unpack(vertex) }` costs ~20 us per vertex.
local function copyOf(source)
    local vertices = {}
    for index = 1, #source do
        local v = source[index]
        vertices[index] = { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8] }
    end
    return vertices
end

local function bounds(vertices)
    local minX, minY, minZ, maxX, maxY, maxZ = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
    local radius = 0
    for _, v in ipairs(vertices) do
        minX, maxX = math.min(minX, v[1]), math.max(maxX, v[1])
        minY, maxY = math.min(minY, v[2]), math.max(maxY, v[2])
        minZ, maxZ = math.min(minZ, v[3]), math.max(maxZ, v[3])
        radius = math.max(radius, math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2))
    end
    return { minX, minY, minZ, maxX, maxY, maxZ }, radius
end

-- An independent, dentable geometry over a shared rest pose.
local function dentable(rest, radius)
    local vertices = copyOf(rest)
    return {
        mesh = katsa.graphics.newMesh(Geometry.format, vertices, 'triangles', 'dynamic'),
        vertices = vertices,
        radius = radius,
        revision = 0,
    }
end

-- Which authored polygons are shaded smooth. A triangle is smooth when a vertex normal differs
-- from its face normal (Blender "Shade Smooth"); flat polygons carry the face normal itself, to
-- float precision. The test must be that fine: a gently curved panel such as the hood bends its
-- normals by well under a degree per triangle, and a coarser limit (the first version used 3.6
-- degrees) took more than half of its triangles for flat ones, which a dent then re-shaded as
-- visible facets. A triangle that shares a corner (position and normal) with a smooth one is smooth
-- as well. The flags and the smoothing groups (corners that share a position and an authored
-- normal) are read once from the rest pose, so a dent keeps every polygon's authored shading.
local FLAT_COS = 0.999999

local function cornerKey(v)
    return string.format('%.4f,%.4f,%.4f|%.2f,%.2f,%.2f', v[1], v[2], v[3], v[6], v[7], v[8])
end

local function analyseShading(rest)
    local smooth, group, ids, count = {}, {}, {}, 0
    local smoothKeys, keys = {}, {}
    for first = 1, #rest - 2, 3 do
        local a, b, c = rest[first], rest[first + 1], rest[first + 2]
        local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
        local wx, wy, wz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
        local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        local length = math.sqrt(nx * nx + ny * ny + nz * nz)
        local round = false
        if length > 1e-12 then
            nx, ny, nz = nx / length, ny / length, nz / length
            for i = 0, 2 do
                local v = rest[first + i]
                -- Either winding: compare the axis, not the facing.
                if math.abs(nx * v[6] + ny * v[7] + nz * v[8]) < FLAT_COS then
                    round = true
                end
            end
        end
        local tri = (first - 1) / 3 + 1
        smooth[tri] = round
        keys[tri] = { cornerKey(a), cornerKey(b), cornerKey(c) }
        if round then
            for i = 1, 3 do
                smoothKeys[keys[tri][i]] = true
            end
        end
    end
    -- Corners shared with a smooth triangle make a triangle smooth too.
    for tri = 1, #rest / 3 do
        if not smooth[tri] then
            for i = 1, 3 do
                if smoothKeys[keys[tri][i]] then
                    smooth[tri] = true
                end
            end
        end
    end
    for tri = 1, #rest / 3 do
        if smooth[tri] then
            for i = 1, 3 do
                local key = keys[tri][i]
                local id = ids[key]
                if not id then
                    count = count + 1
                    id, ids[key] = count, count
                end
                group[(tri - 1) * 3 + i] = id
            end
        end
    end
    return smooth, group, count
end

local TEXTURES = 'scene://textures/duke/'

-- Which generated map set (tools/import/carMaps.py) each part wears. A set lists the maps that
-- exist: color, normal, roughness, metalness. Paint and glass have no tiled maps (their UVs are an
-- atlas / absent), so they use scalar roughness and metalness instead.
local SETS = {
    bottom = { color = 'bottom_color.jpg', normal = 'bottom_normal.png', rough = 'bottom_rough.png', metal = 'bottom_metal.png' },
    interior = { color = 'interior_color.jpg', normal = 'interior_normal.png', rough = 'interior_rough.png', metal = 'interior_metal.png' },
    tire = { color = 'tire_color.jpg', normal = 'tire_normal.png', rough = 'tire_rough.png', metal = 'tire_metal.png' },
    plate = { color = 'plate_color.png', normal = 'plate_normal.png' },
    badges = { color = 'badges_color.png', normal = 'badges_normal.png' },
    lights = { color = 'lights_color.jpg' },
}
local SET_OF = {
    Bottom = 'bottom', Suspension = 'bottom', Bumper_Front = 'bottom', Bumper_Rear = 'bottom',
    Interior = 'interior', Steering_Wheel = 'interior',
    Wheel_FL = 'tire', Wheel_FR = 'tire', Wheel_RL = 'tire', Wheel_RR = 'tire',
    Numberplate_rear = 'plate', Body_Badges = 'badges',
    Brakelights = 'lights', Reverse = 'lights', Headlights = 'lights', Headlights_Glass = 'lights',
}
-- Scalar surface response for parts without maps.
local SCALARS = {
    paint = { roughness = 0.28, metalness = 0.55 },
    glass = { roughness = 0.04, metalness = 0 },
}
-- Glass: nearly clear, a faint cool tint. Alpha is the mesh opacity of the Blend mode.
local GLASS_COLOR = { 0.55, 0.68, 0.78, 0.18 }
local GLASS = {
    Body_Glass = true, Windshield = true, Rear_Glass = true, Glass_Driver = true,
    Glass_Passenger = true,
}

local function material(world, object, part, name)
    local m = part.material or {}
    local set = SETS[SET_OF[name]]
    local scalars = PAINT[name] and SCALARS.paint or (GLASS[name] and SCALARS.glass)
    if not (m.image or set or scalars) then
        return
    end
    local properties = {
        name = 'SurfaceAppearance',
        colorMap = m.image,
        alphaMode = (m.blend or GLASS[name]) and 'Blend'
            or (m.alphaCutoff and m.alphaCutoff > 0 and 'Mask' or 'Inherit'),
        alphaCutoff = m.alphaCutoff,
    }
    if set then
        properties.colorMap = TEXTURES .. set.color
        properties.normalMap = set.normal and TEXTURES .. set.normal
        properties.roughnessMap = set.rough and TEXTURES .. set.rough
        properties.metalnessMap = set.metal and TEXTURES .. set.metal
        -- With a map the scalar multiplies it: leave it neutral.
        properties.roughness = set.rough and 1
        properties.metalness = set.metal and 1
    elseif scalars then
        properties.roughness, properties.metalness = scalars.roughness, scalars.metalness
    end
    world:create('SurfaceAppearance3D', properties, object)
end

CarModel.analyseShading = analyseShading

-- Per rest pose (one per asset part, shared by every car): bounds and shading analysis.
local analysed = setmetatable({}, { __mode = 'k' })

local function analyse(rest)
    local info = analysed[rest]
    if not info then
        local box, radius = bounds(rest)
        local smooth, group, groups = analyseShading(rest)
        info = { box = box, radius = radius + 0.5, smooth = smooth, group = group, groups = groups }
        analysed[rest] = info
    end
    return info
end

function CarModel.available(scene)
    return katsa.filesystem.getInfo(scene.resources:canonical(CarModel.PATH), 'file') ~= nil
end

-- Builds the car under `root`. Returns { wheels = { pivot x4 }, parts = { part ... },
-- paint = { Mesh3D ... } } where a dentable part is { name, object, geometry, rest, box }.
function CarModel.create(scene, root, netId, color)
    local world = scene.world
    local asset = Models.load(CarModel.PATH, scene.resources)
    local result = { wheels = {}, parts = {}, paint = {}, wheelGeometry = {} }
    local pivots = {}
    for _, part in ipairs(asset.parts) do
        local name = part.node.name
        local label = netId .. '_' .. name
        local m = part.material or {}
        if name:match('^Wheel_') then
            local t = part.node.translation
            local pivot = world:create('Node3D', {
                name = 'Car' .. label,
                position = { t[1], t[2], t[3] },
            }, root)
            local mesh = world:create('Mesh3D', {
                name = 'Car' .. label .. 'Mesh',
                geometry = part.geometry,
                color = m.color,
            }, pivot)
            material(world, mesh, part, name)
            pivots[name] = pivot
            result.wheelGeometry[name] = part
        else
            local object = world:create('Mesh3D', {
                name = 'Car' .. label,
                geometry = part.geometry,
                color = PAINT[name] and color or (GLASS[name] and GLASS_COLOR or m.color),
                blend = m.blend or GLASS[name],
                alphaCutoff = m.alphaCutoff,
                doubleSided = m.doubleSided,
            }, root)
            material(world, object, part, name)
            if PAINT[name] then
                result.paint[#result.paint + 1] = object
            end
            if not RIGID[name] then
                local rest = part.geometry.vertices
                local info = analyse(rest)
                result.parts[#result.parts + 1] = {
                    name = name,
                    object = object,
                    shared = part.geometry, -- the asset's geometry, never written
                    geometry = part.geometry, -- the drawn one: shared, or the part's own copy
                    rest = rest,
                    box = info.box,
                    radius = info.radius,
                    smooth = info.smooth,
                    group = info.group,
                    groups = info.groups,
                }
            end
        end
    end
    for index, name in ipairs(CarModel.WHEEL_ORDER) do
        result.wheels[index] = pivots[name]
    end
    return result
end

local function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end

-- Blends a vertex normal toward (nx, ny, nz) by k, keeping it unit length.
local function lean(v, nx, ny, nz, k)
    local mx, my, mz = v[6] * (1 - k) + nx * k, v[7] * (1 - k) + ny * k, v[8] * (1 - k) + nz * k
    local l = math.sqrt(mx * mx + my * my + mz * mz)
    if l > 1e-9 then
        v[6], v[7], v[8] = mx / l, my / l, mz / l
    end
end

-- Re-applies the dents of `deformation` to the rest pose of every part they can reach and uploads
-- the changed meshes. Polygons authored flat are re-shaded flat (face normals) in proportion to
-- how far they moved; polygons authored smooth keep smooth shading from the bent surface.
function CarModel.deform(parts, deformation)
    for _, part in ipairs(parts) do
        local box = part.box
        local reached = deformation:touches(box[1], box[2], box[3], box[4], box[5], box[6])
        if not reached and part.deformed then
            -- Repaired: draw the shared geometry again. The copy is not released here: renderer
            -- caches may still hold its mesh this frame; the collector frees it (Core.track).
            part.geometry = part.shared
            part.object.geometry = part.shared
            part.deformed = false
        elseif reached then
            if part.geometry == part.shared then
                part.geometry = dentable(part.rest, part.radius)
                part.object.geometry = part.geometry
            end
            local rest, vertices = part.rest, part.geometry.vertices
            local moved = part.moved or {}
            part.moved = moved
            for index = 1, #rest do
                local base, v = rest[index], vertices[index]
                local ox, oy, oz = 0, 0, 0
                if reached then
                    ox, oy, oz = deformation:offsetAt(base[1], base[2], base[3])
                end
                v[1], v[2], v[3] = base[1] + ox, base[2] + oy, base[3] + oz
                v[6], v[7], v[8] = base[6], base[7], base[8]
                moved[index] = ox * ox + oy * oy + oz * oz
            end
            if reached then
                -- Face normals of the bent triangles. Flat polygons lean to their own face normal
                -- by how far they moved; smooth polygons add it (area weighted) to the sum of
                -- their smoothing group, so a dented smooth panel stays smooth.
                local smooth, group = part.smooth, part.group
                local sums = part.sums
                if not sums then
                    sums = {}
                    part.sums = sums
                end
                for i = 1, part.groups * 3 do
                    sums[i] = 0
                end
                local faces = part.faces or {}
                part.faces = faces
                for first = 1, #vertices - 2, 3 do
                    local tri = (first - 1) / 3 + 1
                    local a, b, c = vertices[first], vertices[first + 1], vertices[first + 2]
                    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
                    local wx, wy, wz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
                    local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
                    local length = math.sqrt(nx * nx + ny * ny + nz * nz)
                    local face = faces[tri]
                    if not face then
                        face = {}
                        faces[tri] = face
                    end
                    face[4] = length
                    if length > 1e-9 then
                        local fx, fy, fz = nx / length, ny / length, nz / length
                        -- Keep the facing of the authored normal (the winding may differ).
                        if fx * a[6] + fy * a[7] + fz * a[8] < 0 then
                            fx, fy, fz, nx, ny, nz = -fx, -fy, -fz, -nx, -ny, -nz
                        end
                        face[1], face[2], face[3] = fx, fy, fz
                        if smooth[tri] then
                            for i = 0, 2 do
                                local at = group[first + i] * 3 - 2
                                sums[at], sums[at + 1], sums[at + 2] =
                                    sums[at] + nx, sums[at + 1] + ny, sums[at + 2] + nz
                            end
                        end
                    end
                end
                for first = 1, #vertices - 2, 3 do
                    local tri = (first - 1) / 3 + 1
                    local face = faces[tri]
                    if face[4] > 1e-9 then
                        local most = math.max(moved[first], moved[first + 1], moved[first + 2])
                        for i = 0, 2 do
                            local v = vertices[first + i]
                            if smooth[tri] then
                                local k = clamp01(math.sqrt(moved[first + i]) / 0.06)
                                if k > 0 then
                                    local at = group[first + i] * 3 - 2
                                    local sx, sy, sz = sums[at], sums[at + 1], sums[at + 2]
                                    local l = math.sqrt(sx * sx + sy * sy + sz * sz)
                                    if l > 1e-9 then
                                        lean(v, sx / l, sy / l, sz / l, k)
                                    end
                                end
                            else
                                local k = clamp01(math.sqrt(most) / 0.06)
                                if k > 0 then
                                    lean(v, face[1], face[2], face[3], k)
                                end
                            end
                        end
                    end
                end
            end
            part.deformed = true
            part.geometry.mesh:setVertices(vertices)
            part.geometry.revision = part.geometry.revision + 1
        end
    end
end

return CarModel
