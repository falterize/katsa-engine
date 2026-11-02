-- Multi-level navigation: a stack of grids (floors) joined by portals (ramps, stairs, lifts).
-- Every walkable cell has a height, so routes are 3D: an agent can chase a target across the
-- floors of a car park instead of only on one plane.
--
--   local nav = Layered.new(60, 60, { levels = 2, cellSize = 2, origin = { -60, -60 } })
--   nav:bake(
--       function(level, x, z) return level == 1 and groundBlocked(x, z) or deckBlocked(x, z) end,
--       function(level, x, z) return level == 1 and terrain(x, z) or 4.5 end
--   )
--   nav:link(1, rampFootX, rampFootZ, 2, rampTopX, rampTopZ)   -- both directions
--   local path = nav:findPath(x, y, z, targetX, targetY, targetZ)
--   for _, point in ipairs(path.points) do ... end             -- { x, y, z }, path.levels[i]
local AStar = require('source.plugins.pathfinding.astar')
local Path = require('source.plugins.pathfinding.path')
local Grid = require('source.plugins.pathfinding.grid')

local Layered = {}
Layered.__index = Layered

local SQRT2 = math.sqrt(2)
local DIRECTIONS = {
    { 1, 0, 1 },
    { -1, 0, 1 },
    { 0, 1, 1 },
    { 0, -1, 1 },
    { 1, 1, SQRT2 },
    { -1, 1, SQRT2 },
    { 1, -1, SQRT2 },
    { -1, -1, SQRT2 },
}

-- options: levels (default 1), cellSize, origin = { x, z }.
function Layered.new(width, height, options)
    options = options or {}
    local self = setmetatable({
        width = width,
        height = height,
        count = width * height,
        levels = {},
        heights = {},
        portals = {},
        cellSize = options.cellSize or 1,
    }, Layered)
    for level = 1, options.levels or 1 do
        self.levels[level] = Grid.new(width, height, options)
        self.heights[level] = {}
    end
    return self
end

local function node(self, level, cx, cz)
    return (level - 1) * self.count + (cz - 1) * self.width + cx
end

local function decode(self, id)
    local level = math.floor((id - 1) / self.count) + 1
    local rest = (id - 1) % self.count
    return level, rest % self.width + 1, math.floor(rest / self.width) + 1
end

-- Splits a node id into level, cellX, cellZ (used by debug views).
function Layered:decode(id)
    return decode(self, id)
end

-- blocked(level, x, z) -> bool and heightAt(level, x, z) -> y, both in world coordinates.
function Layered:bake(blocked, heightAt)
    for level, grid in ipairs(self.levels) do
        grid:bake(function(x, z)
            return blocked(level, x, z)
        end)
        local heights = self.heights[level]
        for cz = 1, self.height do
            for cx = 1, self.width do
                local x, z = grid:toWorld(cx, cz)
                heights[(cz - 1) * self.width + cx] = heightAt(level, x, z)
            end
        end
    end
end

function Layered:toCell(x, z)
    return self.levels[1]:toCell(x, z)
end

function Layered:isBlocked(level, cx, cz)
    return self.levels[level]:isBlocked(cx, cz)
end

function Layered:heightAtCell(level, cx, cz)
    return self.heights[level][(cz - 1) * self.width + cx]
end

-- Joins two floors at world positions (the cells containing them), in both directions.
function Layered:link(levelA, ax, az, levelB, bx, bz, cost)
    local acx, acz = self:toCell(ax, az)
    local bcx, bcz = self:toCell(bx, bz)
    local a, b = node(self, levelA, acx, acz), node(self, levelB, bcx, bcz)
    local weight = cost or 2
    self.portals[a] = self.portals[a] or {}
    self.portals[b] = self.portals[b] or {}
    table.insert(self.portals[a], { b, weight })
    table.insert(self.portals[b], { a, weight })
end

-- The floor an agent at (x, y, z) stands on: the free cell column whose height is closest to y.
function Layered:levelAt(x, y, z, tolerance)
    local cx, cz = self:toCell(x, z)
    local best, bestGap = nil, tolerance or 2.5
    for level in ipairs(self.levels) do
        if not self:isBlocked(level, cx, cz) then
            local gap = math.abs((self:heightAtCell(level, cx, cz) or 0) - y)
            if gap < bestGap then
                best, bestGap = level, gap
            end
        end
    end
    return best
end

-- Nearest free cell of a level around (cx, cz), searching rings outward.
function Layered:nearestFree(level, cx, cz, radius)
    if self.levels[level]:inside(cx, cz) and not self:isBlocked(level, cx, cz) then
        return cx, cz
    end
    for ring = 1, radius or 3 do
        for dz = -ring, ring do
            for dx = -ring, ring do
                if math.max(math.abs(dx), math.abs(dz)) == ring then
                    local x, z = cx + dx, cz + dz
                    if self.levels[level]:inside(x, z) and not self:isBlocked(level, x, z) then
                        return x, z
                    end
                end
            end
        end
    end
end

local function space(self, goalCx, goalCz)
    local grids = self.levels
    return {
        key = function(id)
            return id
        end,
        neighbors = function(id)
            local level, cx, cz = decode(self, id)
            local grid, result = grids[level], {}
            for _, d in ipairs(DIRECTIONS) do
                local nx, nz = cx + d[1], cz + d[2]
                if not grid:isBlocked(nx, nz) then
                    local free = true
                    if d[3] ~= 1 then
                        free = not grid:isBlocked(nx, cz) and not grid:isBlocked(cx, nz)
                    end
                    if free then
                        result[#result + 1] = node(self, level, nx, nz)
                    end
                end
            end
            for _, portal in ipairs(self.portals[id] or {}) do
                result[#result + 1] = portal[1]
            end
            return result
        end,
        cost = function(from, to)
            local la, ax, az = decode(self, from)
            local lb, bx, bz = decode(self, to)
            if la ~= lb or math.abs(ax - bx) + math.abs(az - bz) > 2 then
                for _, portal in ipairs(self.portals[from] or {}) do
                    if portal[1] == to then
                        return portal[2]
                    end
                end
            end
            local step = (ax ~= bx and az ~= bz) and SQRT2 or 1
            -- Climbing is not free: prefer the flat way around when it is about as short.
            local rise = math.abs((self:heightAtCell(lb, bx, bz) or 0) - (self:heightAtCell(la, ax, az) or 0))
            return step + rise / self.cellSize * 0.5
        end,
        heuristic = function(id)
            local _, cx, cz = decode(self, id)
            local dx, dz = math.abs(cx - goalCx), math.abs(cz - goalCz)
            return (dx + dz) + (SQRT2 - 2) * math.min(dx, dz)
        end,
    }
end

-- Finds a 3D route. Returns a Path whose points are { x, y, z } (y = the floor height there) and
-- whose `levels[i]` is the floor of point i; or nil, reason. options.limit bounds the search.
function Layered:findPath(x0, y0, z0, x1, y1, z1, options)
    options = options or {}
    local levelA, levelB = self:levelAt(x0, y0, z0, 4), self:levelAt(x1, y1, z1, 4)
    if not levelA or not levelB then
        return nil, 'start or goal is not on a walkable floor'
    end
    local acx, acz = self:nearestFree(levelA, self:toCell(x0, z0))
    local bcx, bcz = self:nearestFree(levelB, self:toCell(x1, z1))
    if not acx or not bcx then
        return nil, 'start or goal is blocked'
    end
    local ids, cost = AStar.search(
        space(self, bcx, bcz),
        node(self, levelA, acx, acz),
        node(self, levelB, bcx, bcz),
        options.limit or 6000
    )
    if not ids then
        return nil, cost
    end
    local cells = {}
    for position, id in ipairs(ids) do
        local level, cx, cz = decode(self, id)
        cells[position] = { cx, cz, level }
    end
    if options.smooth ~= false then
        cells = self:smooth(cells)
    end
    local points, levels = {}, {}
    for position, cell in ipairs(cells) do
        local wx, wz = self.levels[cell[3]]:toWorld(cell[1], cell[2])
        points[position] = { wx, self:heightAtCell(cell[3], cell[1], cell[2]) or 0, wz }
        levels[position] = cell[3]
    end
    local path = Path.new(points, cost * self.cellSize)
    path.levels = levels
    return path
end

-- String pulling inside each floor; floor changes are always kept.
function Layered:smooth(cells)
    if #cells <= 2 then
        return cells
    end
    local result, anchor = { cells[1] }, 1
    for candidate = 3, #cells do
        local a, b = cells[anchor], cells[candidate]
        local keep = a[3] ~= b[3] or cells[candidate - 1][3] ~= a[3]
            or not self.levels[a[3]]:lineOfSight(a[1], a[2], b[1], b[2])
        if keep then
            anchor = candidate - 1
            result[#result + 1] = cells[anchor]
        end
    end
    result[#result + 1] = cells[#cells]
    return result
end

return Layered
