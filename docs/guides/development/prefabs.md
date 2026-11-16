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
return require('source.engine.scenes.packed.scene').define(function(scene, context)
    local crate = scene.world:create('Mesh3D', { name = 'Crate', size = { 1, 1, 1 } })
    scene.world:create('SurfaceAppearance3D', { colorMap = 'stone' }, crate)
end)
```

`define` supplies the lifecycle hooks a scene needs; the build function runs once. A prefab scene
may use its own `settings.lua` (`assets`, `nodes`, `plugins`), `scripts/` and `scene://` assets.

## What is copied

- Every node under the scene's World3D with its inspector properties, attributes and tags, in
  order. Node references between copied nodes (properties and attributes) are rebuilt; a reference
  to anything outside the prefab is dropped.
- The world's own Environment, camera and overlay are not copied (a prefab is only content), and
  neither are the nodes an imported model creates: the model file is imported again, so skeletons,
  skins and animation work. Nodes the scene added under an imported bone attach to the model root.
- The scene's resource names (`scene://...`, manifest aliases such as `stone`) are rewritten so the
  importing world finds them; aliases are registered in its manifest as `<sceneId>:<alias>`.
- A world registers meshes by a unique name; a copy of a mesh whose name is taken is registered
  under a suffixed name (`Crate_2`) but keeps showing its own, so paths inside every copy are the same.
- The node types and plugins the scene declares (`settings.nodes`, `settings.plugins`) are registered
  in the receiving world on first use, so their `update`/`start` hooks run in every copy.
  Running a prefab's whole `main.lua` lifecycle (systems) per instance is not supported yet.
- The wrapper has the attribute `ScenePath`.

`packed:require('scripts.data')` returns a module of the prefab scene (data kept next to its nodes).

## Example

replicationLab uses prefabs for all three kinds: `assets/prefabs/avatar` (the character with its
animation tree, one per remote player and bot), `assets/prefabs/player` (the local capsule body
wearing the avatar prefab) and `assets/prefabs/maps/*` (the map of a round; the server places one at
the arena and reads its `scripts/data.lua` for coins and ground height).
