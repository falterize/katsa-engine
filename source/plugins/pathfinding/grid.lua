-- Uniform grid navigation. Cells are 1-based (x = 1..width); world space is
-- origin + (cell - 0.5) * cellSize, so paths pass through cell centers.
local AStar = require('./astar')
local Path = require('./path')

local Grid = {}
Grid.__index = Grid

local SQRT2 = math.sqrt(2)

-- options: cellSize (default 1), origin = { x, y } of the grid's top-left corner (default 0, 0),
-- diagonal (default true), cornerCutting (default false: a diagonal step needs both side cells
-- free).
function Grid.new(width, height, options)
    options = options or {}
    assert(width >= 1 and height >= 1, 'Grid must have at least one cell')
    local self = setmetatable({
        width = width,
        height = height,
        cellSize = options.cellSize or 1,
        originX = options.origin and options.origin[1] or 0,
        originY = options.origin and options.origin[2] or 0,
        diagonal = options.diagonal ~= false,
        cornerCutting = options.cornerCutting == true,
        blocked = {},
        weights = {},
    }, Grid)
    return self
end

function Grid:inside(x, y)
    return x >= 1 and y >= 1 and x <= self.width and y <= self.height
end

local function index(self, x, y)
    return (y - 1) * self.width + x
end

function Grid:setBlocked(x, y, blocked)
    assert(self:inside(x, y), 'Cell is outside the grid')
    self.blocked[index(self, x, y)] = blocked ~= false or nil
    self.revision = (self.revision or 0) + 1
end

function Grid:isBlocked(x, y)
    return not self:inside(x, y) or self.blocked[index(self, x, y)] == true
end

-- Movement cost multiplier for entering a cell (default 1; e.g. 3 for mud). Must be >= 1 so the
-- straight-line heuristic stays admissible.
function Grid:setWeight(x, y, weight)
    assert(self:inside(x, y), 'Cell is outside the grid')
    assert(weight >= 1, 'Cell weight must be at least 1')
    self.weights[index(self, x, y)] = weight ~= 1 and weight or nil
end

-- Blocks (or frees) a rectangle of cells, inclusive.
function Grid:fill(x1, y1, x2, y2, blocked)
    for y = math.max(1, y1), math.min(self.height, y2) do
        for x = math.max(1, x1), math.min(self.width, x2) do
            self:setBlocked(x, y, blocked)
        end
    end
end

-- Samples every cell center: predicate(worldX, worldY) returns true when the cell is blocked.
-- Use it to bake a grid from physics queries or level data.
function Grid:bake(predicate)
    for y = 1, self.height do
        for x = 1, self.width do
            local wx, wy = self:toWorld(x, y)
            self:setBlocked(x, y, predicate(wx, wy))
        end
    end
end

function Grid:toCell(worldX, worldY)
    return math.floor((worldX - self.originX) / self.cellSize) + 1,
        math.floor((worldY - self.originY) / self.cellSize) + 1
end

function Grid:toWorld(x, y)
    return self.originX + (x - 0.5) * self.cellSize, self.originY + (y - 0.5) * self.cellSize
end

-- True when the straight segment between two cells crosses no blocked cell.
function Grid:lineOfSight(x0, y0, x1, y1)
    local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
    local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
    local err = dx - dy
    while true do
        if self:isBlocked(x0, y0) then
            return false
        end
        if x0 == x1 and y0 == y1 then
            return true
        end
        local doubled = err * 2
        local stepX, stepY = doubled > -dy, doubled < dx
        if stepX and stepY and not self.cornerCutting then
            if self:isBlocked(x0 + sx, y0) or self:isBlocked(x0, y0 + sy) then
                return false
            end
        end
        if stepX then
            err, x0 = err - dy, x0 + sx
        end
        if stepY then
            err, y0 = err + dx, y0 + sy
        end
    end
end

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

local function space(self, goalX, goalY)
    local width = self.width
    return {
        key = function(node)
            return node
        end,
        neighbors = function(node)
            local x, y = (node - 1) % width + 1, math.floor((node - 1) / width) + 1
            local result = {}
            for _, direction in ipairs(DIRECTIONS) do
                local nx, ny = x + direction[1], y + direction[2]
                if direction[3] == 1 or self.diagonal then
                    local free = not self:isBlocked(nx, ny)
                    if free and direction[3] ~= 1 and not self.cornerCutting then
                        free = not self:isBlocked(nx, y) and not self:isBlocked(x, ny)
                    end
                    if free then
                        result[#result + 1] = index(self, nx, ny)
                    end
                end
            end
            return result
        end,
        cost = function(from, to)
            local fx, fy = (from - 1) % width, math.floor((from - 1) / width)
            local tx, ty = (to - 1) % width, math.floor((to - 1) / width)
            local step = (fx ~= tx and fy ~= ty) and SQRT2 or 1
            return step * (self.weights[to] or 1)
        end,
        heuristic = function(node)
            local x, y = (node - 1) % width + 1, math.floor((node - 1) / width) + 1
            local dx, dy = math.abs(x - goalX), math.abs(y - goalY)
            if self.diagonal then
                return (dx + dy) + (SQRT2 - 2) * math.min(dx, dy)
            end
            return dx + dy
        end,
    }
end

-- Finds a route between two cells. Returns a list of { x, y } cells, the cost, or nil, reason.
function Grid:findCells(x0, y0, x1, y1, limit)
    if self:isBlocked(x0, y0) or self:isBlocked(x1, y1) then
        return nil, 'start or goal is blocked'
    end
    local nodes, cost, expanded =
        AStar.search(space(self, x1, y1), index(self, x0, y0), index(self, x1, y1), limit)
    if not nodes then
        return nil, cost
    end
    local cells = {}
    for position, node in ipairs(nodes) do
        cells[position] = { (node - 1) % self.width + 1, math.floor((node - 1) / self.width) + 1 }
    end
    return cells, cost * self.cellSize, expanded
end

-- Finds a route between world positions. Returns a Path of cell-center points, or nil, reason.
-- options.smooth removes points that have a clear line of sight (default true).
function Grid:findPath(fromX, fromY, toX, toY, options)
    options = options or {}
    local x0, y0 = self:toCell(fromX, fromY)
    local x1, y1 = self:toCell(toX, toY)
    local cells, cost = self:findCells(x0, y0, x1, y1, options.limit)
    if not cells then
        return nil, cost
    end
    if options.smooth ~= false then
        cells = self:smooth(cells)
    end
    local points = {}
    for position, cell in ipairs(cells) do
        points[position] = { self:toWorld(cell[1], cell[2]) }
    end
    return Path.new(points, cost)
end

-- Drops intermediate cells whose neighbors can see each other (greedy string pulling).
function Grid:smooth(cells)
    if #cells <= 2 then
        return cells
    end
    local result, anchor = { cells[1] }, 1
    for candidate = 3, #cells do
        local a, b = cells[anchor], cells[candidate]
        if not self:lineOfSight(a[1], a[2], b[1], b[2]) then
            anchor = candidate - 1
            result[#result + 1] = cells[anchor]
        end
    end
    result[#result + 1] = cells[#cells]
    return result
end

return Grid
