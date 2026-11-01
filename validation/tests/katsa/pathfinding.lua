-- Pathfinding plugin: grid and graph A*, smoothing, weights, limits and path following.
local P = require('source.plugins.pathfinding')
local SQRT2 = math.sqrt(2)

local function near(a, b)
    return math.abs(a - b) < 1e-6
end

-- Reference: the same grid rules searched with a zero heuristic (plain Dijkstra).
local function dijkstraCost(grid)
    local w = grid.width
    local function isDiagonal(a, b)
        return (a - 1) % w ~= (b - 1) % w and math.floor((a - 1) / w) ~= math.floor((b - 1) / w)
    end
    local space = {
        key = function(node)
            return node
        end,
        neighbors = function(node)
            local px, py = (node - 1) % w + 1, math.floor((node - 1) / w) + 1
            local out = {}
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local nx, ny = px + dx, py + dy
                    local free = (dx ~= 0 or dy ~= 0) and not grid:isBlocked(nx, ny)
                    if free and dx ~= 0 and dy ~= 0 then
                        free = not grid:isBlocked(nx, py) and not grid:isBlocked(px, ny)
                    end
                    if free then
                        out[#out + 1] = (ny - 1) * w + nx
                    end
                end
            end
            return out
        end,
        cost = function(a, b)
            return isDiagonal(a, b) and SQRT2 or 1
        end,
        heuristic = function()
            return 0
        end,
    }
    local _, cost = P.AStar.search(space, 1, w * grid.height)
    return type(cost) == 'number' and cost or nil
end

local function gridChecks(T)
    local open = P.Grid.new(10, 10)
    local cells, cost = open:findCells(1, 1, 10, 1)
    T.check(cells and #cells == 10 and near(cost, 9), 'pathfinding: corridor costs its length')
    cells, cost = open:findCells(1, 1, 5, 5)
    T.check(near(cost, 4 * SQRT2), 'pathfinding: open diagonal is the shortest route')

    local wall = P.Grid.new(10, 10)
    wall:fill(5, 1, 5, 9, true)
    cells, cost = wall:findCells(1, 5, 10, 5)
    local passesGap = false
    for _, cell in ipairs(cells) do
        passesGap = passesGap or cell[1] == 5 and cell[2] == 10
    end
    T.check(passesGap and cost > 9, 'pathfinding: route detours through the only gap')
    wall:fill(5, 10, 5, 10, true)
    T.check(wall:findCells(1, 5, 10, 5) == nil, 'pathfinding: sealed wall has no path')
    T.check(wall:findCells(5, 5, 10, 5) == nil, 'pathfinding: blocked start has no path')
    T.check(open:findCells(1, 1, 10, 10, 3) == nil, 'pathfinding: search limit stops queries')

    local corner = P.Grid.new(3, 3)
    corner:setBlocked(2, 1, true)
    corner:setBlocked(1, 2, true)
    T.check(corner:findCells(1, 1, 3, 3) == nil, 'pathfinding: corners are not cut')
    local cutting = P.Grid.new(3, 3, { cornerCutting = true })
    cutting:setBlocked(2, 1, true)
    cutting:setBlocked(1, 2, true)
    T.check(cutting:findCells(1, 1, 3, 3) ~= nil, 'pathfinding: corner cutting is optional')

    local mud = P.Grid.new(5, 3, { diagonal = false })
    for x = 2, 4 do
        mud:setWeight(x, 2, 5)
    end
    local detour = 0
    for _, cell in ipairs(mud:findCells(1, 2, 5, 2)) do
        detour = detour + (cell[2] ~= 2 and 1 or 0)
    end
    T.check(detour > 0, 'pathfinding: weighted cells are avoided when cheaper')
end

local function worldChecks(T)
    local world = P.Grid.new(20, 20, { cellSize = 10, origin = { 100, 200 } })
    local x, y = world:toWorld(1, 1)
    T.check(x == 105 and y == 205, 'pathfinding: cell centers map to world space')
    local cx, cy = world:toCell(105, 205)
    T.check(cx == 1 and cy == 1, 'pathfinding: world positions map to cells')
    world:fill(10, 1, 10, 15, true)
    local path = world:findPath(105, 205, 295, 205)
    T.check(path ~= nil and #path.points >= 3, 'pathfinding: findPath returns world points')
    local raw = world:findCells(1, 1, 19, 1)
    T.check(#path.points < #raw, 'pathfinding: smoothing removes visible points')
    local px, py, steps = 105, 205, 0
    while not path:isFinished() and steps < 500 do
        local dx, dy = path:direction(px, py, nil, 3)
        px, py = px + dx * 2, py + dy * 2
        steps = steps + 1
    end
    T.check(path:isFinished() and steps < 500, 'pathfinding: direction() leads an agent home')
end

local function randomChecks(T)
    math.randomseed(7)
    local worst = 0
    for _ = 1, 30 do
        local grid = P.Grid.new(14, 14)
        for _ = 1, 45 do
            grid:setBlocked(math.random(14), math.random(14), true)
        end
        grid:setBlocked(1, 1, false)
        grid:setBlocked(14, 14, false)
        local _, cost = grid:findCells(1, 1, 14, 14)
        local reference = dijkstraCost(grid)
        if (type(cost) == 'number') ~= (reference ~= nil) then
            worst = math.huge
        elseif reference then
            worst = math.max(worst, math.abs(cost - reference))
        end
    end
    T.check(worst < 1e-6, 'pathfinding: A* cost equals Dijkstra on random maps')
end

local function graphChecks(T)
    local graph = P.Graph.new()
    graph:addNode('a', 0, 0, 0)
    graph:addNode('b', 10, 0, 0)
    graph:addNode('c', 10, 10, 0)
    graph:addNode('d', 0, 10, 5)
    graph:connect('a', 'b')
    graph:connect('b', 'c')
    graph:connect('c', 'd')
    graph:connect('a', 'd', 4)
    local route = graph:findPath('a', 'd')
    local expected = 20 + math.sqrt(125)
    T.check(route and #route.points == 4 and near(route.cost, expected), 'pathfinding: graph route')
    T.check(graph:nearest(9, 1, 0) == 'b', 'pathfinding: graph snaps to the nearest node')
    graph:addNode('lonely', 100, 100, 0)
    T.check(graph:findPath('a', 'lonely') == nil, 'pathfinding: unreachable graph node')
    local between = graph:findPathBetween(1, 1, 0, 9, 9, 0)
    T.check(between ~= nil and #between.points == 3, 'pathfinding: graph path between points')
end

return function(T)
    gridChecks(T)
    worldChecks(T)
    randomChecks(T)
    graphChecks(T)
end
