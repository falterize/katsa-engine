-- Convex decomposition and hull reduction.
--
--   Decompose.simplify(points, maxPoints)  one convex hull with at most `maxPoints` vertices
--   Decompose.run(soup, options)           several convex hulls that together follow the model
--
-- `run` is the "Multiple Convex" collision shape: the model is voxelised, the planner cuts it into
-- nearly convex regions (planner.lua), and each region keeps the real triangles inside it, clipped
-- to the region's box, so every hull is as tight as the mesh itself and neighbouring hulls touch
-- exactly at their cuts.
local Clip = require('./clip')
local Directions = require('./directions')
local Grid = require('./voxelGrid')
local Hull = require('./hull')
local Planner = require('./planner')

local Decompose = {}

Decompose.defaults = {
    resolution = 32, -- voxels along the longest side used to judge concavity
    maxHulls = 8, -- most convex pieces
    concavity = 0.02, -- stop cutting a piece that leaves less than this share of the volume empty
    hullPoints = 32, -- most vertices per piece
}

-- Merges points closer than `tolerance` (keeps the first of each cell).
local function dedupe(points, tolerance)
    local seen, result = {}, {}
    for i = 1, #points do
        local p = points[i]
        local key = math.floor(p[1] / tolerance + 0.5)
            .. ':'
            .. math.floor(p[2] / tolerance + 0.5)
            .. ':'
            .. math.floor(p[3] / tolerance + 0.5)
        if not seen[key] then
            seen[key] = true
            result[#result + 1] = p
        end
    end
    return result
end

local function extent(points)
    local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for i = 1, #points do
        for axis = 1, 3 do
            lo[axis] = math.min(lo[axis], points[i][axis])
            hi[axis] = math.max(hi[axis], points[i][axis])
        end
    end
    return math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
end

-- The vertices of the convex hull of `points`, reduced to at most `maxPoints` by keeping the
-- points that stick out furthest along well-spread directions. A flat set gets a little thickness
-- so a solid shape can be built from it. Returns nil for fewer than two distinct points.
function Decompose.simplify(points, maxPoints)
    maxPoints = math.max(4, maxPoints or Decompose.defaults.hullPoints)
    local size = extent(points)
    if size <= 0 then
        return nil
    end
    local unique = dedupe(points, size * 1e-6)
    if #unique > 300 then
        -- The hull builder is quadratic; a dense cloud keeps only its silhouette first.
        unique = Directions.extremes(unique, Directions.rich(192))
    end
    local hull = Hull.compute(unique)
    if not hull then
        local thick = Hull.thicken(unique, math.max(size * 0.02, 0.005))
        hull = thick and Hull.compute(thick)
        if not hull then
            return nil
        end
    end
    if #hull.vertices <= maxPoints then
        return hull.vertices
    end
    local reduced = Directions.extremes(hull.vertices, Directions.rich(maxPoints))
    local again = Hull.compute(reduced)
    return again and again.vertices or hull.vertices
end

-- Box bounds of a planner region in model coordinates; sides on the grid's outer boundary stay open.
local function bounds(grid, leaf)
    local lo, hi = {}, {}
    local origin = { grid.originX, grid.originY, grid.originZ }
    local count = { grid.nx, grid.ny, grid.nz }
    for axis = 1, 3 do
        lo[axis] = leaf.lo[axis] > 0 and origin[axis] + leaf.lo[axis] * grid.size or false
        hi[axis] = leaf.hi[axis] < count[axis] and origin[axis] + leaf.hi[axis] * grid.size or false
    end
    return lo, hi
end

local function outside(a, b, c, lo, hi)
    for axis = 1, 3 do
        local low = math.min(a[axis], b[axis], c[axis])
        local high = math.max(a[axis], b[axis], c[axis])
        if (hi[axis] and low > hi[axis]) or (lo[axis] and high < lo[axis]) then
            return true
        end
    end
    return false
end

local function inside(a, b, c, lo, hi)
    for axis = 1, 3 do
        local low = math.min(a[axis], b[axis], c[axis])
        local high = math.max(a[axis], b[axis], c[axis])
        if (lo[axis] and low < lo[axis]) or (hi[axis] and high > hi[axis]) then
            return false
        end
    end
    return true
end

-- soup: list of { x, y, z }, three per triangle. Returns a list of vertex lists (one convex hull
-- each) and a table of statistics. Always returns at least one hull.
function Decompose.run(soup, options)
    local settings = {}
    for key, value in pairs(Decompose.defaults) do
        settings[key] = value
    end
    for key, value in pairs(options or {}) do
        settings[key] = value
    end
    assert(#soup >= 3 and #soup % 3 == 0, 'Decomposition needs a triangle list')
    if settings.maxHulls <= 1 then
        local single = Decompose.simplify(soup, settings.hullPoints)
        return { single }, { hulls = 1, voxels = 0 }
    end
    local grid = Grid.build(soup, settings.resolution)
    local leaves, stats = Planner.plan(grid, settings)
    local hulls = {}
    for _, leaf in ipairs(leaves) do
        local lo, hi = bounds(grid, leaf)
        local points = {}
        for t = 1, #soup - 2, 3 do
            local a, b, c = soup[t], soup[t + 1], soup[t + 2]
            if not outside(a, b, c, lo, hi) then
                if inside(a, b, c, lo, hi) then
                    points[#points + 1], points[#points + 2], points[#points + 3] = a, b, c
                else
                    local clipped = Clip.polygon({ a, b, c }, lo, hi)
                    for i = 1, clipped and #clipped or 0 do
                        points[#points + 1] = clipped[i]
                    end
                end
            end
        end
        if #points >= 3 then
            local hull = Decompose.simplify(points, settings.hullPoints)
            if hull then
                hulls[#hulls + 1] = hull
            end
        end
    end
    if #hulls == 0 then
        hulls[1] = Decompose.simplify(soup, settings.hullPoints)
    end
    stats.hulls = #hulls
    return hulls, stats
end

return Decompose
