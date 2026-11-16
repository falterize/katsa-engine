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
the scene that uses it, in `assets/prefabs/<name>/` (`settings.lua`, `main.lua`, `scripts/`, its own
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

`build` builds the content (everything under the scene's `World3D` and on its `World2D` overlay).
The hooks are the usual scene lifecycle (`create`, `update2D`, `update`, `update3D`, `destroy`) and
run for **every copy**, inside the scene that holds it ("a scene in a scene"): `scene` is the host
scene with its own `scene.world`, `scene.resources`, `scene.settings`, `scene.package` and
`scene.node` (the copy's Node3D); everything else (`scene.physics`, `scene.input` ...) is the host's.
`scene.world:create` puts spatial nodes under the copy and understands the prefab's own resource
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

## What is copied

- Every node under the scene's World3D with its inspector properties, attributes and tags, in
  order. Node references between copied nodes (properties and attributes) are rebuilt; a reference
  to anything outside the prefab is dropped.
- Cameras are copied but never become the current camera. The scene's own Environment and
  overlay container are not copied (a prefab is only content); what the scene put on its World2D
  overlay is shown on the overlay of the receiving world and goes away with the copy. Nodes with
  their own UI (BillboardUI, SurfaceUI ...) keep their UI children. Neither are the nodes an
  imported model creates copied: the model file is imported again, so skeletons,
  skins and animation work. Nodes the scene added under an imported bone attach to the model root.
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
