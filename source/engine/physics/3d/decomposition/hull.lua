-- Incremental 3D convex hull.
--
-- Hull.compute(points) takes a list of { x, y, z } and returns
--     { vertices = { {x, y, z}, ... }, faces = { {i, j, k}, ... }, volume = number }
-- (faces are counter-clockwise seen from outside, indices into `vertices`), or nil plus a reason
-- ('point', 'line' or 'flat') when the points do not span a volume. Only hull vertices are kept.
--
-- The algorithm keeps a conflict-free list of faces: for each new point it removes the faces that
-- can see it, finds the horizon (edges between a removed and a kept face) and joins the horizon to
-- the point. That is O(points * faces), fast for the few hundred points this module receives
-- (callers reduce large clouds with Directions.extremes first).
local Hull = {}

local sqrt, abs = math.sqrt, math.abs

-- Largest side of the bounding box; the tolerances below are relative to it.
local function extent(points)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for i = 1, #points do
        local p = points[i]
        local x, y, z = p[1], p[2], p[3]
        if x < minX then
            minX = x
        end
        if x > maxX then
            maxX = x
        end
        if y < minY then
            minY = y
        end
        if y > maxY then
            maxY = y
        end
        if z < minZ then
            minZ = z
        end
        if z > maxZ then
            maxZ = z
        end
    end
    return math.max(maxX - minX, maxY - minY, maxZ - minZ)
end

-- Picks four points that span a tetrahedron. Returns indices, or nil plus the degenerate kind
-- and (for a flat set) the plane normal.
local function initialSimplex(points, eps)
    local lo, hi = { 1, 1, 1 }, { 1, 1, 1 }
    for i = 2, #points do
        local p = points[i]
        for axis = 1, 3 do
            if p[axis] < points[lo[axis]][axis] then
                lo[axis] = i
            end
            if p[axis] > points[hi[axis]][axis] then
                hi[axis] = i
            end
        end
    end
    -- The farthest pair among the six axis extremes.
    local a, b, best = lo[1], hi[1], -1
    for axis = 1, 3 do
        local p, q = points[lo[axis]], points[hi[axis]]
        local d = (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2
        if d > best then
            a, b, best = lo[axis], hi[axis], d
        end
    end
    if best < eps * eps then
        return nil, 'point'
    end
    local pa, pb = points[a], points[b]
    local dx, dy, dz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
    local length = sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / length, dy / length, dz / length
    -- Third point: farthest from the line a-b.
    local c, far = nil, eps
    for i = 1, #points do
        local p = points[i]
        local rx, ry, rz = p[1] - pa[1], p[2] - pa[2], p[3] - pa[3]
        local t = rx * dx + ry * dy + rz * dz
        local ox, oy, oz = rx - t * dx, ry - t * dy, rz - t * dz
        local d = sqrt(ox * ox + oy * oy + oz * oz)
        if d > far then
            c, far = i, d
        end
    end
    if not c then
        return nil, 'line'
    end
    local pc = points[c]
    local ex, ey, ez = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
    local nx, ny, nz = dy * ez - dz * ey, dz * ex - dx * ez, dx * ey - dy * ex
    local nl = sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / nl, ny / nl, nz / nl
    -- Fourth point: farthest from the plane a-b-c.
    local d4, farPlane = nil, eps
    for i = 1, #points do
        local p = points[i]
        local d = abs((p[1] - pa[1]) * nx + (p[2] - pa[2]) * ny + (p[3] - pa[3]) * nz)
        if d > farPlane then
            d4, farPlane = i, d
        end
    end
    if not d4 then
        return nil, 'flat', { nx, ny, nz }
    end
    return { a, b, c, d4 }
end

local function newFace(points, a, b, c)
    local pa, pb, pc = points[a], points[b], points[c]
    local ux, uy, uz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
    local vx, vy, vz = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local length = sqrt(nx * nx + ny * ny + nz * nz)
    if length > 1e-30 then
        nx, ny, nz = nx / length, ny / length, nz / length
    else
        nx, ny, nz = 0, 0, 0
    end
    return {
        a = a,
        b = b,
        c = c,
        nx = nx,
        ny = ny,
        nz = nz,
        d = nx * pa[1] + ny * pa[2] + nz * pa[3],
        alive = true,
        mark = 0,
    }
end

function Hull.compute(points)
    local count = #points
    if count < 4 then
        return nil, count == 0 and 'point' or 'flat'
    end
    local eps = math.max(extent(points) * 1e-7, 1e-12)
    local simplex, kind, normal = initialSimplex(points, eps)
    if not simplex then
        return nil, kind, normal
    end
    local a, b, c, d = simplex[1], simplex[2], simplex[3], simplex[4]
    local first = newFace(points, a, b, c)
    local pd = points[d]
    if first.nx * pd[1] + first.ny * pd[2] + first.nz * pd[3] - first.d > 0 then
        b, c = c, b -- flip so that the fourth point lies behind the first face
    end

    local stride = count + 1
    local edges = {} -- directed edge a * stride + b -> the live face that owns it
    local faces = {}

    local function add(i, j, k)
        local face = newFace(points, i, j, k)
        faces[#faces + 1] = face
        edges[i * stride + j] = face
        edges[j * stride + k] = face
        edges[k * stride + i] = face
        return face
    end

    -- Tetrahedron with outward faces: abc, bad, cbd, acd.
    add(a, b, c)
    add(b, a, d)
    add(c, b, d)
    add(a, c, d)

    local used = { [a] = true, [b] = true, [c] = true, [d] = true }
    local stamp, live = 0, 4
    for index = 1, count do
        if not used[index] then
            local p = points[index]
            local px, py, pz = p[1], p[2], p[3]
            stamp = stamp + 1
            local visible, seen = {}, 0
            for i = 1, #faces do
                local face = faces[i]
                if face.alive and face.nx * px + face.ny * py + face.nz * pz - face.d > eps then
                    face.mark = stamp
                    seen = seen + 1
                    visible[seen] = face
                end
            end
            if seen > 0 then
                -- Horizon: directed edges of visible faces whose twin face stays.
                local horizon = {}
                for i = 1, seen do
                    local face = visible[i]
                    local f1, f2, f3 = face.a, face.b, face.c
                    local e = { f1, f2, f2, f3, f3, f1 }
                    for k = 1, 6, 2 do
                        local twin = edges[e[k + 1] * stride + e[k]]
                        if not twin or twin.mark ~= stamp then
                            horizon[#horizon + 1] = { e[k], e[k + 1] }
                        end
                    end
                end
                for i = 1, seen do
                    local face = visible[i]
                    face.alive = false
                    edges[face.a * stride + face.b] = nil
                    edges[face.b * stride + face.c] = nil
                    edges[face.c * stride + face.a] = nil
                end
                for i = 1, #horizon do
                    add(horizon[i][1], horizon[i][2], index)
                end
                live = live - seen + #horizon
                -- Dropping dead faces now and then keeps the scan above short.
                if #faces > 2 * live + 32 then
                    local kept = {}
                    for i = 1, #faces do
                        if faces[i].alive then
                            kept[#kept + 1] = faces[i]
                        end
                    end
                    faces = kept
                end
            end
        end
    end

    -- Collect: compact vertex numbering, faces by new indices, volume by the divergence theorem
    -- around the vertex centroid (stable for hulls far from the origin).
    local remap, vertices, result = {}, {}, {}
    local cx, cy, cz = 0, 0, 0
    for i = 1, #faces do
        local face = faces[i]
        if face.alive then
            local indices = { face.a, face.b, face.c }
            for k = 1, 3 do
                local old = indices[k]
                if not remap[old] then
                    local p = points[old]
                    vertices[#vertices + 1] = { p[1], p[2], p[3] }
                    remap[old] = #vertices
                    cx, cy, cz = cx + p[1], cy + p[2], cz + p[3]
                end
                indices[k] = remap[old]
            end
            result[#result + 1] = indices
        end
    end
    local n = #vertices
    cx, cy, cz = cx / n, cy / n, cz / n
    local volume = 0
    for i = 1, #result do
        local f = result[i]
        local v1, v2, v3 = vertices[f[1]], vertices[f[2]], vertices[f[3]]
        local ax, ay, az = v1[1] - cx, v1[2] - cy, v1[3] - cz
        local bx, by, bz = v2[1] - cx, v2[2] - cy, v2[3] - cz
        local qx, qy, qz = v3[1] - cx, v3[2] - cy, v3[3] - cz
        volume = volume
            + (ax * (by * qz - bz * qy) + ay * (bz * qx - bx * qz) + az * (bx * qy - by * qx)) / 6
    end
    return { vertices = vertices, faces = result, volume = abs(volume) }
end

-- Cheap shape test (no hull is built): 'solid' when the points span a volume, otherwise 'flat',
-- 'line' or 'point'; a flat set also returns its plane normal.
function Hull.classify(points)
    if #points == 0 then
        return 'point'
    end
    local eps = math.max(extent(points) * 1e-7, 1e-12)
    local simplex, kind, normal = initialSimplex(points, eps)
    if simplex then
        return 'solid'
    end
    return kind, normal
end

-- Gives a flat set some thickness (+-`thickness` along its normal) so a convex shape can be built
-- from it. Solid sets come back unchanged; a point or a line returns nil.
function Hull.thicken(points, thickness)
    local kind, normal = Hull.classify(points)
    if kind == 'solid' then
        return points
    end
    if kind ~= 'flat' or not normal then
        return nil
    end
    thickness = thickness or 0.03
    local result = {}
    for _, p in ipairs(points) do
        result[#result + 1] =
            { p[1] + normal[1] * thickness, p[2] + normal[2] * thickness, p[3] + normal[3] * thickness }
        result[#result + 1] =
            { p[1] - normal[1] * thickness, p[2] - normal[2] * thickness, p[3] - normal[3] * thickness }
    end
    return result
end

return Hull
