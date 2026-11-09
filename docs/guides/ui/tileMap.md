# TileMap

`TileMap` draws a grid of cells from a tileset. Each cell holds a tile id, so a level is data you
can paint, save and query, not a pile of sprites. It is a UI node (a `Frame`), so it works as a HUD
element or as a visual under a 2D body.

## Tileset

A tileset is a Lua file that returns a table (`assets/tilesets/platformer.lua` is the example):

```lua
return {
    image = 'shared://textures/examples/tileset.png',
    columns = 8, rows = 3,                         -- tile grid; ids are 0-based, row by row
    terrains = { ground = { tiles = ground, solid = true } },
    tiles = { [16] = { name = 'water', hazard = true }, [17] = { name = 'brick', solid = true } },
}
```

- `tiles[id]` holds free properties (`solid`, `name`, `damage` ...). Read them with `map:tileProperty(x, y, 'damage')`.
- A **terrain** is an autotile: 16 ids, one per mask of neighbouring cells (N=1, E=2, S=4, W=8). Paint with
  `map:setTerrain(x, y, 'ground')` and the edge tiles (grass on top, borders on the open sides) follow the
  neighbours, also when you erase a cell.

## The node

```lua
local map = ui:create('TileMap', {
    tileSet = 'shared://tilesets/platformer.lua',
    cellSize = { 32, 32 },                         -- on-screen size of a cell
    size = { 0, 960, 0, 480 },
}, ui.content)
map:fillTerrain(0, 12, 29, 14, 'ground', 'Ground', ui)
map:setCell(10, 8, 20, 'Decor')                    -- plain id on another layer
local x, y = map:cellAt(px, py)                    -- cell under a point
```

Cells are `(x, y)` integers, `y` grows downward and `(0, 0)` is the top-left corner of the node.
Layers are named and drawn in creation order (`getLayer`, `setLayerVisible`, `clear`). Only the cells inside the
node and on screen are drawn, so a large map costs what it shows.

| Property | Meaning |
| --- | --- |
| `tileSet` | tileset file (or a table) |
| `mapFile` | Lua file with cells saved by `toData`, loaded when it changes |
| `cellSize` | size of one cell, UI pixels |
| `pixelate` | sharp pixels (default on) |
| `interactable` | on: the signal `cellPointer(phase, x, y, id)` reports press / move / release over cells |

## Collision

`map:solidRects(layer)` merges solid cells into few rectangles; `map:buildColliders(ui, body, { origin = { x, y } })`
creates a `Collider2D` box per rectangle under a static `Body2D`. `origin` is where the map's top-left corner is
relative to the body (physics units, Y up). Call it again after editing and the old boxes are replaced.
`map:isSolid(x, y)` answers for one cell, e.g. to build a pathfinding `Grid`.

## Saving

`map:toData()` returns plain data (layers with `{x, y, id}` cells) and `map:loadData(data)` restores it. Write the
table as a Lua file for `mapFile`.

Examples: scene `tileMapLab` (paint, layers, collision overlay, snapshot) and the ground of `abilityRunner2D`.
Tests: `validation/tests/versions/v108_7/tileMap.lua`. The example tileset is made by `tools/import/makeTileset.py`.
