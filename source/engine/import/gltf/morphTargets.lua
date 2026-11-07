local ffi = require('ffi')

-- Reads glTF morph targets (Blender "Shape Keys") into compact per-part blend shape data.
--
-- glTF stores, per primitive, one POSITION (and optionally NORMAL) delta per target. The mesh
-- carries the shape names (`mesh.extras.targetNames`, written by the Blender exporter) and the
-- default weights (`mesh.weights`). The runtime lives in graphics/geometry/blendShapes.lua.
local MorphTargets = {}

-- Names and default weights shared by every primitive of one glTF mesh.
function MorphTargets.describe(mesh)
    local first = mesh.primitives[1]
    local count = first and first.targets and #first.targets or 0
    if count == 0 then
        return nil
    end
    local names, defaults = {}, {}
    local authored = mesh.extras and mesh.extras.targetNames or {}
    for t = 1, count do
        names[t] = authored[t] or ('Shape' .. t)
        defaults[t] = mesh.weights and mesh.weights[t] or 0
    end
    return { names = names, defaults = defaults, count = count }
end

local function expand(delta, corners)
    local out = ffi.new('float[?]', #corners * 3)
    if delta then
        for i, source in ipairs(corners) do
            local d = delta[source]
            out[i * 3 - 3], out[i * 3 - 2], out[i * 3 - 1] = d[1], d[2], d[3]
        end
    end
    return out
end

-- Per-corner deltas of one primitive. `corners[i]` is the accessor index of the i-th triangle
-- corner, so the arrays line up with the non-indexed vertex list.
function MorphTargets.read(accessor, primitive, corners, shared)
    assert(
        #primitive.targets == shared.count,
        'Every primitive of a GLB mesh needs the same number of morph targets'
    )
    local data = { positions = {}, normals = {}, corners = #corners }
    for t, target in ipairs(primitive.targets) do
        data.positions[t] = expand(target.POSITION and accessor(target.POSITION), corners)
        data.normals[t] = target.NORMAL and expand(accessor(target.NORMAL), corners) or false
    end
    return data
end

-- Restricts corner data to the vertices of one draw batch (`origin[i]` = corner index of its
-- i-th vertex) and records the unmorphed positions and normals.
function MorphTargets.part(data, shared, vertices, origin)
    local n = #vertices
    local part = {
        _assetGeometry = true, -- shared by every model instance (see Models.load)
        names = shared.names,
        defaults = shared.defaults,
        count = shared.count,
        n = n,
        basePosition = ffi.new('float[?]', n * 3),
        baseNormal = ffi.new('float[?]', n * 3),
        positions = {},
        normals = {},
    }
    for i, v in ipairs(vertices) do
        local at = i * 3 - 3
        part.basePosition[at], part.basePosition[at + 1], part.basePosition[at + 2] = v[1], v[2], v[3]
        part.baseNormal[at], part.baseNormal[at + 1], part.baseNormal[at + 2] = v[6], v[7], v[8]
    end
    for t = 1, shared.count do
        local sourceP, sourceN = data.positions[t], data.normals[t]
        local positions = ffi.new('float[?]', n * 3)
        local normals = sourceN and ffi.new('float[?]', n * 3) or false
        for i = 1, n do
            local from, to = (origin and origin[i] or i) * 3 - 3, i * 3 - 3
            for c = 0, 2 do
                positions[to + c] = sourceP[from + c]
                if normals then
                    normals[to + c] = sourceN[from + c]
                end
            end
        end
        part.positions[t], part.normals[t] = positions, normals
    end
    return part
end

-- A part's morph data restricted to `origin` (origin[i] = index in `part` of the new i-th vertex),
-- used when skin limits split a draw into several batches.
function MorphTargets.slice(part, origin)
    local n = #origin
    local result = {
        _assetGeometry = true,
        names = part.names,
        defaults = part.defaults,
        count = part.count,
        n = n,
        basePosition = ffi.new('float[?]', n * 3),
        baseNormal = ffi.new('float[?]', n * 3),
        positions = {},
        normals = {},
    }
    local function copy(from, to)
        for i = 1, n do
            local source, target = origin[i] * 3 - 3, i * 3 - 3
            for c = 0, 2 do
                to[target + c] = from[source + c]
            end
        end
    end
    copy(part.basePosition, result.basePosition)
    copy(part.baseNormal, result.baseNormal)
    for t = 1, part.count do
        result.positions[t] = ffi.new('float[?]', n * 3)
        copy(part.positions[t], result.positions[t])
        if part.normals[t] then
            result.normals[t] = ffi.new('float[?]', n * 3)
            copy(part.normals[t], result.normals[t])
        else
            result.normals[t] = false
        end
    end
    return result
end

return MorphTargets
