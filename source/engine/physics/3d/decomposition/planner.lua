-- Plans a decomposition into convex pieces by recursive axis-aligned cuts of a voxel grid
-- (the idea of V-HACD, kept small).
--
-- A region of cells is "concave" by how much its convex hull exceeds the cells it really holds.
-- The planner repeatedly takes the most concave region and cuts it at the plane that leaves the
-- least concavity in the two halves, until every region is nearly convex or the piece budget is
-- spent. The hull of a region is approximated by its extreme cells along 26 directions, found
-- once per slab, so every candidate plane costs two tiny hulls instead of a pass over the cells.
local Directions = require('./directions')
local Hull = require('./hull')

local Planner = {}

local DIRS = Directions.lattice()
local K = #DIRS
local NEG = -math.huge

local function emptySlab()
    return { value = {}, x = {}, y = {}, z = {} }
end

-- Keeps, per direction, the better of two extreme tables. `into` may alias `a`.
local function merge(into, a, b)
    for d = 1, K do
        if b.value[d] ~= nil and (a.value[d] == nil or b.value[d] > a.value[d]) then
            into.value[d], into.x[d], into.y[d], into.z[d] = b.value[d], b.x[d], b.y[d], b.z[d]
        elseif into ~= a then
            into.value[d], into.x[d], into.y[d], into.z[d] = a.value[d], a.x[d], a.y[d], a.z[d]
        end
    end
    return into
end

local function copy(slab)
    local result = emptySlab()
    for d = 1, K do
        result.value[d], result.x[d], result.y[d], result.z[d] =
            slab.value[d], slab.x[d], slab.y[d], slab.z[d]
    end
    return result
end

-- Volume of the hull of the extreme points of a slab table (nil without a solid hull).
local function hullVolume(extremes)
    local points = {}
    for d = 1, K do
        if extremes.value[d] ~= nil then
            points[#points + 1] = { extremes.x[d], extremes.y[d], extremes.z[d] }
        end
    end
    local hull = Hull.compute(points)
    return hull and hull.volume
end

-- One pass over a region: cell count and, for each axis, the count and extremes of every slab.
local function analyse(grid, region)
    local lo, hi = region.lo, region.hi
    local size, half = grid.size, grid.size * 0.5
    local ox, oy, oz = grid.originX, grid.originY, grid.originZ
    local slabs, counts = {}, {}
    for axis = 1, 3 do
        slabs[axis], counts[axis] = {}, {}
        for s = 0, hi[axis] - lo[axis] - 1 do
            slabs[axis][s] = emptySlab()
            counts[axis][s] = 0
        end
    end
    local total = 0
    local sx, sy, sz = slabs[1], slabs[2], slabs[3]
    for k = lo[3], hi[3] - 1 do
        for j = lo[2], hi[2] - 1 do
            for i = lo[1], hi[1] - 1 do
                if grid:isFilled(i, j, k) then
                    total = total + 1
                    local cx, cy, cz = ox + (i + 0.5) * size, oy + (j + 0.5) * size, oz + (k + 0.5) * size
                    local a, b, c = sx[i - lo[1]], sy[j - lo[2]], sz[k - lo[3]]
                    counts[1][i - lo[1]] = counts[1][i - lo[1]] + 1
                    counts[2][j - lo[2]] = counts[2][j - lo[2]] + 1
                    counts[3][k - lo[3]] = counts[3][k - lo[3]] + 1
                    for d = 1, K do
                        local dir = DIRS[d]
                        local dx, dy, dz = dir[1], dir[2], dir[3]
                        local value = dx * cx + dy * cy + dz * cz
                        for n = 1, 3 do
                            local slab = n == 1 and a or (n == 2 and b or c)
                            local best = slab.value[d]
                            if best == nil or value > best then
                                slab.value[d] = value
                                slab.x[d] = cx + (dx > 0 and half or (dx < 0 and -half or 0))
                                slab.y[d] = cy + (dy > 0 and half or (dy < 0 and -half or 0))
                                slab.z[d] = cz + (dz > 0 and half or (dz < 0 and -half or 0))
                            end
                        end
                    end
                end
            end
        end
    end
    return { count = total, slabs = slabs, counts = counts }
end

local function concavity(hull, count, cell)
    if not hull then
        return 0
    end
    return math.max(0, hull - count * cell)
end

-- Finds the cut with the least leftover concavity. Returns nil when no cut separates anything.
local function bestCut(grid, region, data)
    local cell = grid.size ^ 3
    local best
    for axis = 1, 3 do
        local length = region.hi[axis] - region.lo[axis]
        if length >= 2 then
            local slabs, counts = data.slabs[axis], data.counts[axis]
            -- Suffix extremes and counts for every cut position p (cells p..length-1).
            local suffix, suffixCount = {}, {}
            local running, runningCount = emptySlab(), 0
            for p = length - 1, 1, -1 do
                running = merge(copy(running), running, slabs[p])
                runningCount = runningCount + counts[p]
                suffix[p], suffixCount[p] = running, runningCount
            end
            local prefix, prefixCount = emptySlab(), 0
            for p = 1, length - 1 do
                prefix = merge(copy(prefix), prefix, slabs[p - 1])
                prefixCount = prefixCount + counts[p - 1]
                if prefixCount > 0 and suffixCount[p] > 0 then
                    local left = concavity(hullVolume(prefix), prefixCount, cell)
                    local right = concavity(hullVolume(suffix[p]), suffixCount[p], cell)
                    -- A small preference for even halves keeps cuts away from thin slivers.
                    local imbalance = math.abs(prefixCount - suffixCount[p])
                        / (prefixCount + suffixCount[p])
                    local score = (left + right) * (1 + 0.1 * imbalance)
                    if not best or score < best.score then
                        best = {
                            axis = axis,
                            at = region.lo[axis] + p,
                            score = score,
                            leftConcavity = left,
                            rightConcavity = right,
                            leftCount = prefixCount,
                            rightCount = suffixCount[p],
                        }
                    end
                end
            end
        end
    end
    return best
end

-- Returns the leaf regions { lo = {i,j,k}, hi = {i,j,k} } (hi exclusive) plus statistics.
-- options: maxHulls (>= 1), concavity (fraction of the model's volume a region may leave).
function Planner.plan(grid, options)
    local cell = grid.size ^ 3
    local root = { lo = { 0, 0, 0 }, hi = { grid.nx, grid.ny, grid.nz } }
    local data = analyse(grid, root)
    local all = emptySlab()
    for slab = 0, grid.nx - 1 do
        all = merge(copy(all), all, data.slabs[1][slab])
    end
    local whole = hullVolume(all)
    root.count = data.count
    root.concavity = concavity(whole, data.count, cell)
    local totalVolume = data.count * cell
    local limit = (options.concavity or 0.02) * totalVolume
    local leaves = { root }
    local splits = 0
    while #leaves < (options.maxHulls or 8) do
        local pick
        for _, leaf in ipairs(leaves) do
            if not leaf.final and leaf.concavity > limit and (not pick or leaf.concavity > pick.concavity) then
                pick = leaf
            end
        end
        if not pick then
            break
        end
        local cut = bestCut(grid, pick, analyse(grid, pick))
        if not cut or cut.score >= pick.concavity * 0.98 then
            pick.final = true -- cutting does not help; keep it as one piece
        else
            local a = { lo = { pick.lo[1], pick.lo[2], pick.lo[3] }, hi = { pick.hi[1], pick.hi[2], pick.hi[3] } }
            local b = { lo = { pick.lo[1], pick.lo[2], pick.lo[3] }, hi = { pick.hi[1], pick.hi[2], pick.hi[3] } }
            a.hi[cut.axis], b.lo[cut.axis] = cut.at, cut.at
            a.count, a.concavity = cut.leftCount, cut.leftConcavity
            b.count, b.concavity = cut.rightCount, cut.rightConcavity
            for i, leaf in ipairs(leaves) do
                if leaf == pick then
                    leaves[i] = a
                    break
                end
            end
            leaves[#leaves + 1] = b
            splits = splits + 1
        end
    end
    return leaves, { voxels = data.count, splits = splits, concavity = root.concavity / totalVolume }
end

return Planner
