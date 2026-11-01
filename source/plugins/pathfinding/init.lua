-- Pathfinding plugin: A* on grids and waypoint graphs.
--
--   local pathfinding = require('source.engine.plugins').require('pathfinding')
--   local grid = pathfinding.Grid.new(64, 64, { cellSize = 32 })
--   grid:fill(10, 1, 10, 40, true)
--   local path = grid:findPath(x, y, targetX, targetY)
--   local dx, dy = path:direction(x, y, nil, 8)   -- steer an agent toward the next point
return {
    Grid = require('source.plugins.pathfinding.grid'),
    Graph = require('source.plugins.pathfinding.graph'),
    Path = require('source.plugins.pathfinding.path'),
    AStar = require('source.plugins.pathfinding.astar'),
}
