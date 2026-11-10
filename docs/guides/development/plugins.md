# Plugins

A plugin is an optional add-on that lives in `source/plugins/<name>/`. The core engine never
requires a plugin, so a build or game that does not use one pays nothing and can leave the
folder out. Pathfinding and ads are the shipped plugins; further add-ons follow the same layout.

```text
source/plugins/pathfinding/
  plugin.lua    manifest (see below)
  init.lua      entry; returns the plugin API
  nodes/        node types the plugin adds (one module per node)
  extensions/   settings and methods the plugin adds to existing node classes
  debug.lua     optional debug drawing
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

## Bundled plugins

| Plugin | What it adds |
| --- | --- |
| `pathfinding` | A* on grids, graphs and multi-floor maps, a baked NavMesh with obstacles and crowds, the `NavMap3D`, `NavAgent3D` and `NavObstacle3D` nodes, a debug view |
| `uiStyler` | UI style sheets and `assets/styles` files, themes switchable at runtime (`docs/guides/ui/uiStyler.md`) |
| `ik` | `InverseKinematics3D` node with TwoBone, CCD, FABRIK, Jacobian, Spline, LookAt and FK types (`docs/guides/animation/ik.md`) |

## Enabling a plugin in a scene

List the plugin in the scene's `settings.lua`:

```lua
return {
    id = 'myScene',
    plugins = { 'pathfinding' },   -- activates the plugin's contributions for this scene
}
```

`Plugins.activate(world, names)` runs when the scene loads (the scene host and the game runtime
call it right after `nodes` are registered). A scene that does not list the plugin sees none of
its node types, debug sections or editor entries. `Plugins.require` alone only loads the Lua API.

## What a manifest can contribute

```lua
return {
    name = 'pathfinding', title = 'Pathfinding', version = '1.2.0',
    description = '...', requires = {},

    -- 1. New node types, registered like world:registerNodeType (module returns the definition).
    nodes = { NavMap3D = './nodes.navMap3D' },

    -- 2. Settings and methods added to EXISTING node classes.
    extend = { Body3D = './extensions.body3D' },

    -- 3. Debug sections: Environment.debug.<key>, drawn after the 3D scene when enabled.
    --    One table (its defaults are the section's properties), or a list of tables.
    debug = { key = 'pathfinding', title = 'Pathfinding',
              defaults = { enabled = false, drawCells = true, drawLinks = true,
                           drawPaths = true, drawDistance = 40 },
              draw = './debug' },
}
```

### Node types (`nodes`)

A module returns the same definition table `world:registerNodeType(name, definition)` takes:
`base`, `properties` (descriptors with `default`, `min`, `max`, `hint`), `initialize`, `update`
and any methods. Properties appear in the editor inspector with their hints.

### Extending existing nodes (`extend`)

The module returns an extension spec; it is applied through
`source/engine/nodes/core/extensions.lua`:

```lua
-- source/plugins/pathfinding/extensions/body3D.lua
return {
    properties = {                        -- new settings, shown in the inspector with defaults
        navWalkable = { default = true, hint = 'NavMap3D baking takes this collider into account.' },
        navFloor = { default = 0, min = 0, hint = 'The NavMap3D floor this collider is the ground of.' },
    },
    methods = {                           -- optional: functions added to the class
        navCost = function(self) return self.navFloor == 0 and 1 or 2 end,
    },
    initialize = function(node) end,      -- optional: runs for every node created afterwards
}
```

Scripts then use the settings like built-ins: `world:create('Body3D', { navFloor = 2, ... })`,
`body.navWalkable = false`. Node classes are global, so an extension applies to nodes created
after the first scene activated the plugin in this process. Property or method names that
already exist are an error, so two plugins cannot silently clash.

### Debug sections (`debug`)

The `defaults` table becomes `Environment.debug.<key>`; it is listed under *Environment → Debug*
in the editor and as a toggle in the debug menu (`<title> debug`). When `enabled` is true the
renderer calls `draw(world, camera, settings)` of the module every frame, after the 3D scene and
the physics debug. Drawing uses `camera:project({x, y, z})` and `katsa.graphics` lines.

```lua
-- minimal debug module
return {
    draw = function(world, camera, settings)
        local x, y = camera:project({ 0, 1, 0 })
        if x then katsa.graphics.circle('fill', x, y, 6) end
    end,
}
```

Add a new plugin by creating the folder and manifest only; the engine needs no edits.

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

## Multi-floor maps (`Layered`)

`pathfinding.Layered.new(width, height, { levels = 2, cellSize = 2, origin = { x, z } })` stacks
grids (floors) joined by portals (ramps). `bake(blocked(level, x, z), heightAt(level, x, z))`
fills them, `link(levelA, ax, az, levelB, bx, bz)` adds a portal, `levelAt(x, y, z)` tells which
floor a point is on and `findPath(x0, y0, z0, x1, y1, z1)` returns a `Path` of `{x, y, z}` points
with `path.levels[i]`.

## NavMap3D node

`NavMap3D` (enable the plugin in the scene) bakes a `Layered` map from the physics world, so the
navigation sees exactly what bodies collide with:

```lua
local map = world:create('NavMap3D', {
    position = { 0, 0, 0 },        -- region centre
    areaSize = { 120, 120 },       -- width (X) and depth (Z)
    cellSize = 2,
    floors = 2,                    -- storeys; colliders pick theirs with Body3D.navFloor
    castTop = 20, castBottom = -2, -- ray range relative to the node
    agentRadius = 1.5, agentHeight = 1.5, maxSlope = 35, maxStep = 0.6,
})
map:bake()                                     -- returns the number of walkable cells
local path = map:findPath({ x, y, z }, { tx, ty, tz })   -- Path, or nil, reason
local floor = map:levelAt(x, y, z)
local layered = map:getMap()                   -- the Layered map, for custom queries
```

Baking casts one ray per cell and floor straight down. A cell is walkable when the surface is
flatter than `maxSlope`, has `agentHeight` of free space above it, and has no height jump larger
than `maxStep` next to it; blocked cells grow by whole cells of `agentRadius`. Floor 1 sees
colliders with `navFloor` 0 or 1, floor *n* sees colliders with `navFloor = n`; every collider
blocks headroom. A collider with `navWalkable = false` is ignored completely. Floors are linked
where their free cells meet at a similar height (the foot of a ramp). Keep slabs at least as
thick as `agentHeight` or tag them so rays from the upper floor do not start inside them.

### NavMesh, obstacles and crowds

Every `bake()` also builds a **NavMesh**: the walkable cells merged into convex polygons (tiles of
`meshTile` cells, polygons stay flatter than `meshFlatness`), one layer per floor, joined at ramps.

```lua
local path = map:findSmoothPath({ x, y, z }, { tx, ty, tz })   -- corners only, funnel-straightened
local obstacle = map:addObstacle({ kind = 'circle', x = 10, z = 4, radius = 2 })
map:moveObstacle(obstacle, 12, 4)
map:removeObstacle(obstacle)
```

Obstacles cover cells (grown by `agentRadius`) and mark their tiles dirty; the next query rebuilds
only those tiles, so doors and crates cost little. `findPath` keeps using the cell grid.

Nodes (the scene needs the plugin; both look for the first baked NavMap3D when `navMap` is empty):

- `NavObstacle3D`: `shape` Circle/Box, `radius`, `size`, `height`, `blocking`. It follows the node's transform.
- `NavAgent3D` (Godot style): a technical node (base `Node`, no transform, size or transparency) that plans routes
  and advises; it never moves anything. Create it as a child of the body and set `feetOffset` (distance from the
  body origin down to the feet), or use `agent:setPosition({ x, y, z })`. Move the body yourself each step: `getNextPathPosition()` (corner to walk to), `getVelocity()` (wanted velocity
  with neighbours avoided), `getNextAction()` / `getActionTarget()` (link action ahead and where it ends),
  `isNavigationFinished()`, `isTargetReached()`, `getDistanceToTarget()`, `getPath()`. Properties: `speed`,
  `radius`, `height`, `pathDesiredDistance`, `targetDesiredDistance`, `pathMaxDistance`, `avoidance`, `targetNode`,
  `areaCosts`, `actionCosts`; methods `setTarget({x, y, z})`, `clearTarget()`; signals `Arrived`, `PathFailed`,
  `LinkReached`. The route is renewed when the mesh changes, the target moves or the body strays more than
  `pathMaxDistance` (never while a body is in the air during an action).
  Agents of one map form a crowd: velocity-sampling avoidance, at most four repaths per frame.
- Size: the agent's size is **not** measured. The map is baked for one body (`NavMap3D.agentRadius`, `agentHeight`,
  `maxStep`, `maxSlope`); `NavAgent3D.radius`/`height` only describe the agent so the read-only `fits` /
  `fitProblem` can say when the baked clearance is too tight (`NavMap3D:getClearance()`).

Tests: `v108_7/navMesh.lua` (core) and `v108_7/navNodes.lua` (real bake, obstacle, agent).

### Areas, action links and per-agent weights

Weights live in the **agent**, never in the map or the link, so one NavMap3D serves agents that choose
differently. Anything not set uses a default (every area costs 1, `jump` 2, other actions 1).

- `NavArea3D`: an axis-aligned box (`size`) that names the walkable cells inside it (`area = 'water'`,
  `active`, optional `navMap`). Polygons never mix areas. The area has no cost of its own.
- `NavLink3D`: joins two places the mesh cannot walk between and names the action (`action = 'jump'`, `'climb'`,
  `'door'` or any word). The end is `endNode` or the node position plus `endOffset`; `bidirectional`, `active`
  (turn a door or bridge on and off), `arcHeight` and `duration` are hints stored for your script. Code can add
  links too: `map:addLink({ from = {x,y,z}, to = {x,y,z}, action = 'jump' })`, `map:removeLink(link)`,
  `map:setLinkEnabled(link, false)`; the lower-level `mesh:addLink` takes cell-exact points.
- `NavAgent3D.areaCosts` / `actionCosts`: text such as `water = 50, mud = 3` and `jump = 3, climb = off`. A number
  multiplies the cost of walking in the area or crossing a link of that action; `off` (or `false` in code, via
  `agent:setAreaCost('water', false)` / `setActionCost`) forbids it. A large number is a last resort: the agent
  wades through water only when no other way exists. Routes use `mesh:findPath(from, to, { areaCosts = ..., actionCosts = ... })`.

**The plugin does not perform actions.** While an agent is on its way to a link start, `getNextAction()` returns
the action ('jump', 'climb', 'door' ...), `getNextPathPosition()` is the link start and `getActionTarget()` the far
end. Your script does the action however it likes (a Character that presses jump, a tween, an animation); the
agent goes on as soon as the body stands near the far end (`LinkReached` is emitted then). A missed jump simply
leaves the route and a new one is planned. `navMeshLab` shows the physical version
(`behaviors/physicalWalker.lua`): walkers use the StareShooter character model, animations and controller
(`source/game/characters`) on a capsule body. They follow the advised
velocity; at a jump link they press jump close to the start, so the body leaves with the controller's jump power and its running speed, and steer in the air toward the landing like a player (less input when the landing
is near); a climb link drives the body up the ladder with gravity off. The jump links themselves are found by
`behaviors/jumpLinks.lua`. Keep `maxStep` at what the body can climb and `agentHeight` at the body height.

The debug view draws action links under `drawLinks` (orange arcs for `jump`, magenta for `climb`, cyan for other
actions, grey while disabled; hand-made links show their action's name) and agent routes under `drawPaths`.

Tests: `v108_7/navLinks.lua`, and the lab checks in `v108_7/labScenes.lua`.

### Pathfinding debug view

Turn on *Pathfinding debug* in the debug menu, or `world.environment.debug.pathfinding.enabled = true`.
It draws the walkable cells of every baked NavMap3D (one colour per floor), white lines for floor
links and the most recent routes (yellow lines with a dot per waypoint). `drawDistance` limits
the cells drawn around the camera; `drawCells`, `drawLinks`, `drawPaths` switch the parts.

Example scene script:

```lua
-- settings.lua: plugins = { 'pathfinding' }
local map = scene.world:create('NavMap3D', { areaSize = { 100, 100 }, cellSize = 2 })
map:bake()
scene.world.environment.debug.pathfinding.enabled = true
local path = map:findPath({ -30, 0, -30 }, { 30, 0, 30 })
-- steer an agent: local tx, ty, tz = path:target(agent.x, agent.y, agent.z, 3)
```


### Choosing `cellSize`, `agentRadius` and narrow passages

All NavMap3D sizes are world units (they do not depend on `physics.unitsPerMeter`; scale them
yourself in scenes built at another scale). `cellSize` accepts 0.05 and up; bake time and memory
grow roughly as `1 / cellSize^2` (a 40 x 40 area is 6 400 cells at 0.5, 25 600 at 0.25 and 160 000
at 0.1). Blocked cells grow by `floor(agentRadius / cellSize)` whole cells, and a walker's centre
stays `(rings + 0.5) * cellSize` away from a wall, so the margin is a multiple of the cell. For a
1.2 m passage and a 0.4 m capsule use `cellSize = 0.25`, `agentRadius = 0.4` (one ring, 0.375 m
margin). Keep `agentRadius` close to the real body radius: a larger value closes narrow passages,
a smaller one lets the body scrape walls.

# Ads plugin

Provider-neutral rewarded video ads (`source/plugins/ads`):

```lua
local Ads = Plugins.require('ads')
Ads.configure({ provider = 'admob', rewardedUnit = 'ca-app-pub-xxxx/yyyy' })   -- your own ids
Ads.load()
if Ads.isRewardedReady() then
    Ads.showRewarded(function(result) if result.rewarded then grantReward() end end)
end
-- call Ads.update(dt) every frame
```

Providers: `mock` (development; plays a fake ad for `mockDuration` seconds, `mockSkip = true`
simulates closing early), `admob` (the most widely used network; reached through the host's
`katsa.platform.ads` bridge on Android/iOS) and `unity` (`katsa.platform.unityAds`). Another SDK
is added with `Ads.registerProvider(name, { load, isReady, show, update })`. Without a bridge a
provider reports `unavailable` instead of failing, so the same game runs on desktop.

A client claim is not proof that an ad was watched. The multiplayerCars server grants the reward
through `options.verifyReward(player, token)` (plug in the network's server-side verification)
and limits refills with a per-player cooldown. Keep your ids in
`scenes/multiplayerCars/scripts/game/adsConfig.lua`; the file ships Google's public test unit.
