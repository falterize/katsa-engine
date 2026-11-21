# Scenes as prefabs

Any scene can be used as a prefab, like a Godot `PackedScene`. The scene is loaded once, in a
private world, with its normal `main.lua`; what it built under its `World3D` becomes a template.
`instantiate` builds a fresh copy of that content under a `Node3D` in any world.

```lua
local enemy = world.prefabs:load('scene://prefabs/enemy')       -- once; cached per world
local boss = enemy:instantiate({
    name = 'Boss',
    position = { 0, 0, 20 },                                      -- the wrapper Node3D's properties
    overrides = { ['Body/Head'] = { color = { 1, 0, 0 } } },      -- properties of nodes by path
}, parentNode)                                                    -- parent defaults to the world
boss:find('Body/Head')                                            -- paths work as everywhere
world.prefabs:instantiate('scene://prefabs/enemy', { name = 'Grunt' })  -- load + instantiate
```

## Where the scene is

`load` takes what a scene normally is: a folder, an archive (`.zip`/`.katsa`), a `FileData`, or a
`scene://` / `shared://` path of the current scene's assets. A prefab scene usually lives next to
the scene that uses it, in `assets/prefabs/<name>/` (`conf.lua`, `main.lua`, `scripts/`, its own
`assets/`). Plain relative paths work too (`game/scenes/x`, `context.root .. '/../avatar'`);
prefabs can instantiate other prefabs.

## Writing a prefab scene

```lua
-- assets/prefabs/crate/main.lua
local Prefab = require('source.engine.scenes.packed.scene')

local function build(scene, context)             -- runs once, when the scene is packed
    local crate = scene.world:create('Mesh3D', { name = 'Crate', size = { 1, 1, 1 } })
    scene.world:create('SurfaceAppearance3D', { colorMap = './scene://textures/wood.png' }, crate)
    scene.world:create('BillboardUI', { name = 'Plate' }, crate) -- BillboardUI, SurfaceUI, World2D ...
end

return Prefab.define(build, {                    -- the hooks are optional
    create = function(scene, context) return { hits = 0 } end,   -- once per copy
    update = function(state, dt) end,                            -- every frame, per copy
    destroy = function(state) end,                               -- when the copy is destroyed
})
```

`build` builds the content (everything under the scene's `World3D` and in its `World2D`).
The hooks are the usual scene lifecycle (`create`, `update2D`, `update`, `update3D`, `destroy`) and
run for **every copy**, inside the scene that holds it ("a scene in a scene"): `scene` is the host
scene with its own `scene.world`, `scene.resources`, `scene.settings`, `scene.package` and
`scene.node` (the copy's Node3D); everything else (`scene.physics`, `scene.input` ...) is the host's.
`scene.world:create` puts spatial nodes under the copy, UI and 2D nodes into the copy's own World2D (`scene:world2d()`, made on first use) and understands the prefab's own resource
names, and `scene.world.prefabs` resolves paths against the prefab. The modules of the scene's
`systems/` folder are created per copy (`create(state, scene, context)`) and updated with it
(order through `define(build, { systems = { name = { order = 20 } } })`). Copies are updated by
`world:updateNodes(dt)`, like custom node types, which a prefab scene may also declare
(`settings.nodes`, `settings.plugins`). A scene without a `build` hook is packed by running its
`create`, and starts no scripts.

## Paths

`scene://x` in a prefab is an asset of the prefab scene; `./scene://x` is the same, and
`../scene://x` is an asset of the scene that loaded it (`../../scene://x` one more up, `./` is
ignored: as with Lua module paths). A prefab inside a prefab uses the same: the avatar prefab is
loaded by `'../scene://prefabs/avatar'` from the player prefab. Manifest aliases of the prefab's
`settings.assets` work too.

Paths are rewritten when a node is built (the `build` hook, `scene.world:create`). A string a
script assigns to an existing node later (`node.colorMap = 'scene://x.png'`) is not rewritten,
because the node does not know which scene wrote it, and `scene://` then means the scene that holds
the world. For that, and for using a prefab's assets from outside it, every loaded prefab answers
to its own name as a scheme:

```lua
world.prefabs:load('scene://prefabs/apple')                      -- the name is the scene id: 'apple'
world.prefabs:load('scene://prefabs/apple', { name = 'fruit' })  -- or a name of your choice
node.colorMap = 'apple://textures/ripe.png'                       -- same file from anywhere
```

Names are letters, digits, `_` and `-`; `scene` and `shared` are reserved. They are registered in
the world's asset roots, so any node and any script of that world reads them. A name you give in
`{ name = ... }` must be valid and free, otherwise `load` raises an error. The default name (the
scene id) goes to the first scene that has it: a scene whose id is not a valid name (`my prefab`,
`shared`) or is taken still loads, it just has no `<id>://`, so give such scenes a `name`.
`scene.resources:canonical('scene://x.png')`
also turns a prefab's own path into the real one.

## What is copied

- Every node under the scene's World3D with its inspector properties, attributes and tags, in
  order. Node references between copied nodes (properties and attributes) are rebuilt; a reference
  to anything outside the prefab is dropped.
- Cameras are copied but never become the current camera. The scene's own Environment is not
  copied (a prefab is only content). Its **World2D is copied as a World2D node** inside the copy's Node3D
  (`Crate/World2D`): each copy has its own interface with the scene's HUD content, Node2D/Camera2D
  children and World2D properties (`timeScale`, `gravity`, `transparency`, `layerGroup`,
  `currentCamera`). It works like any interface of the world above it and is destroyed with the
  copy. Other World2D nodes the scene created are copied the same way. Nodes with their own UI (BillboardUI, SurfaceUI ...) keep their
  UI children. Neither are the nodes an imported model creates copied: the model file is
  imported again, so skeletons, skins and animation work. Nodes the scene added under an imported
  bone attach to the model root.
- The scene's resource names (`scene://...`, manifest aliases such as `stone`) are rewritten so the
  importing world finds them; aliases are registered in its manifest as `<sceneId>:<alias>`.
- A world registers meshes by a unique name; a copy of a mesh whose name is taken is registered
  under a suffixed name (`Crate_2`) but keeps showing its own, so paths inside every copy are the same.
- The node types and plugins the scene declares (`settings.nodes`, `settings.plugins`) are registered
  in the receiving world on first use, so their `update`/`start` hooks run in every copy.
- The wrapper has the attribute `ScenePath`.

`packed:require('scripts.data')` returns a module of the prefab scene (data kept next to its nodes).

## Example

replicationLab uses prefabs for all three kinds: `assets/prefabs/avatar` (the character with its
animation tree, one per remote player and bot), `assets/prefabs/player` (the local capsule body
wearing the avatar prefab) and `assets/prefabs/maps/*` (the map of a round; the server places one at
the arena and reads its `scripts/data.lua` for coins and ground height).

## World2D inside any node

A World2D may be a child of any node, not only of its World3D: `world:create('World2D', props,
holder)`. It belongs to the first World3D above it, covers the screen like before (its position in
the tree has no spatial meaning), is listed in `world.uis` and leaves with its parent. It cannot
sit inside a widget, another World2D or a different World3D.

Inside a `ViewportFrame` it is the interface of that viewport: a prefab copy placed in the
viewport's World3D keeps its World2D there (drawn into the viewport, clickable in it), and the
viewport world loads packed scenes with the scene manager of the world that holds the frame.

<!-- book:nav -->
---
**Katsa book** · chapter 2, Scenes and nodes · page 5 of 8

[← Node authoring and API reference](nodeAuthoring.md) · [Contents](../../book/README.md) · [Spatial transforms (v45) →](spatialTransforms.md)
<!-- /book:nav -->
