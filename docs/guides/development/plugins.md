# Plugins

A plugin is an optional add-on that lives in `source/plugins/<name>/`. The core engine never
requires a plugin, so a build or game that does not use one pays nothing and can leave the
folder out. Pathfinding is the first plugin; further add-ons (ads providers, extra importers)
follow the same layout.

```text
source/plugins/pathfinding/
  plugin.lua    manifest: name, title, version, description, requires = { other plugins }
  init.lua      entry; returns the plugin API
  ...           implementation modules, one concern per file
```

```lua
local Plugins = require('source.engine.plugins')
local pathfinding = Plugins.require('pathfinding')   -- loads once, dependencies first
Plugins.names()                                      -- folders present in this build
Plugins.manifest('pathfinding')                      -- manifest table, or nil
```

The manifest `name` must equal the folder name. Plugins are ordinary Lua packages inside the
project: they are packed into `.katsa` archives and fused executables with everything else.

# Pathfinding plugin

A* with a generic search core (`astar.lua`: neighbors, cost and heuristic come from the map),
a binary-heap open set and two maps.

```lua
local pathfinding = require('source.engine.plugins').require('pathfinding')

-- Grid (2D or top-down 3D): cells are 1-based; paths pass through cell centers.
local grid = pathfinding.Grid.new(64, 64, { cellSize = 32, origin = { 0, 0 } })
grid:fill(10, 1, 10, 40, true)                 -- block a rectangle
grid:setWeight(5, 5, 3)                        -- slow terrain (>= 1)
grid:bake(function(x, y) return solidAt(x, y) end) -- or sample the world
local path = grid:findPath(x, y, targetX, targetY, { smooth = true, limit = 5000 })

-- Steering: call every frame; radius is how close counts as "reached".
local dx, dy = path:direction(agent.x, agent.y, nil, 8)

-- Waypoint graph (3D levels, roads)
local graph = pathfinding.Graph.new()
graph:addNode('a', 0, 0, 0); graph:addNode('b', 10, 0, 0)
graph:connect('a', 'b')
local route = graph:findPathBetween(x, y, z, tx, ty, tz)
```

Diagonal moves are allowed by default and may not cut corners (`cornerCutting = true`
enables it). `limit` caps expanded nodes. Failed searches return `nil, reason`
(`'no path'`, `'search limit reached'`, `'start or goal is blocked'`). Heuristics are
admissible, so routes are optimal; tests compare costs with Dijkstra on random maps.
A NavMesh for arbitrary 3D geometry is not included; author or generate waypoint graphs.
