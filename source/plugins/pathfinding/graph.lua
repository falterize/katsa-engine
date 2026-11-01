-- Waypoint graph for 3D levels, roads or any map where nodes are authored or generated.
-- Node ids are strings or numbers; positions are { x, y [, z] }.
local AStar = require('source.plugins.pathfinding.astar')
local Path = require('source.plugins.pathfinding.path')

local Graph = {}
Graph.__index = Graph

function Graph.new()
    return setmetatable({ positions = {}, edges = {} }, Graph)
end

function Graph:addNode(id, x, y, z)
    self.positions[id] = { x, y, z or 0 }
    self.edges[id] = self.edges[id] or {}
    return id
end

-- Connects two nodes. `weight` multiplies the straight distance (default 1, must be >= 1);
-- `oneWay` makes the edge directed.
function Graph:connect(a, b, weight, oneWay)
    assert(self.positions[a] and self.positions[b], 'Both nodes must exist before connecting')
    weight = weight or 1
    assert(weight >= 1, 'Edge weight must be at least 1')
    self.edges[a][b] = weight
    if not oneWay then
        self.edges[b][a] = weight
    end
end

function Graph:disconnect(a, b)
    self.edges[a][b], self.edges[b][a] = nil, nil
end

local function distance(p, q)
    local dx, dy, dz = p[1] - q[1], p[2] - q[2], p[3] - q[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Nearest node to a position (optionally within `radius`), or nil.
function Graph:nearest(x, y, z, radius)
    local here, best, bestDistance = { x, y, z or 0 }, nil, radius or math.huge
    for id, position in pairs(self.positions) do
        local d = distance(here, position)
        if d <= bestDistance then
            best, bestDistance = id, d
        end
    end
    return best
end

function Graph:findNodes(from, to, limit)
    local space = {
        neighbors = function(id)
            local list = {}
            for neighbor in pairs(self.edges[id]) do
                list[#list + 1] = neighbor
            end
            table.sort(list, function(a, b)
                return tostring(a) < tostring(b)
            end)
            return list
        end,
        cost = function(a, b)
            return distance(self.positions[a], self.positions[b]) * self.edges[a][b]
        end,
        heuristic = function(a, goal)
            return distance(self.positions[a], self.positions[goal])
        end,
    }
    return AStar.search(space, from, to, limit)
end

-- Route between node ids. Returns a Path through the node positions, or nil, reason.
function Graph:findPath(from, to, limit)
    assert(self.positions[from] and self.positions[to], 'Unknown node')
    local ids, cost = self:findNodes(from, to, limit)
    if not ids then
        return nil, cost
    end
    local points = {}
    for index, id in ipairs(ids) do
        local p = self.positions[id]
        points[index] = { p[1], p[2], p[3] }
    end
    return Path.new(points, cost)
end

-- Route between positions: snaps both ends to the nearest nodes.
function Graph:findPathBetween(x0, y0, z0, x1, y1, z1, limit)
    local from, to = self:nearest(x0, y0, z0), self:nearest(x1, y1, z1)
    if from == nil or to == nil then
        return nil, 'graph is empty'
    end
    return self:findPath(from, to, limit)
end

return Graph
