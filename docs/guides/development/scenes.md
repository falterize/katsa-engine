# Scene authoring

Each scene is a self-contained folder. Its code, UI, custom nodes and systems
live together; a scene does not delegate its implementation to another scene
or a shared full-scene factory. Shared engine services remain in `source/engine`.

```text
source/game/scenes/exampleScene/
    settings.lua
    main.lua
    assets/
        models/
        textures/
        audio/
        shaders/
        fonts/
    nodes/
    systems/
    scripts/
        content.lua
        builders/
        behaviors/
        lighting/
        animation/
        data/
        catalog/
        ui/
            interface.lua
            panels/
            previews/
            examples/
            world/
```

The assets, nodes, systems and scripts categories, scripts/ui, and the listed
asset subdirectories are required,
including unused ones. Other helper subcategories are created only when needed.
Project and scene packers write directory entries explicitly, so empty categories
survive ZIP/.katsa, TAR and supported 7z packaging without marker files. Category and module
names are case-sensitive and follow the existing lower camel case convention.
`init.lua` is not a scene entry point.

The required categories above are mandatory. Other internal script/UI subcategories
are created only when used; do not add empty categories for every possible feature.
`content.lua` is the scene composition entry, not a container for unrelated helpers.
Keep the rest of `scripts/` organized by responsibility:

| Category | Content |
| --- | --- |
| `scripts/builders/` | Level, object and rig construction |
| `scripts/behaviors/` | Scene behavior and abilities used by systems/content |
| `scripts/lighting/` | Directional lighting setup and day/night behavior |
| `scripts/animation/` | Scene-specific clips and animation helpers |
| `scripts/data/` | Declarative scene layouts and other authored data |
| `scripts/catalog/` | Example catalog routing and sample helpers |

`scripts/ui/interface.lua` builds a gameplay interface; camera-free interfaces use
`scripts/ui/controller.lua` as their state/controller entry. Additional UI modules go beneath scripts/ui,
under `panels`, `previews`, `examples` or `world` according to their purpose.
`systems/` retains direct executable modules because the visible `main.lua` loop
loads them. Helpers used by those modules belong under categorized `scripts/`.

## Starting a game

Set `startScene` in `source/game/data/project.lua` to a scene ID, project-relative
scene directory or archive. The default `menu` is an example selector for testing;
a game can start directly in its own scene without loading the selector.

The optional `source/game/sceneCatalog.lua` maps stable IDs to folders or archives.
Add an entry only when the ID should be available for navigation or the example
selector. A direct folder/archive path needs no catalog entry. Menu metadata comes
from each scene's settings. The common gameplay host is `source/game/runtime/game.lua`.
Camera-free menu/pause/catalog scenes use `engine/scenes/interface.lua` instead;
their implementation still lives inside their own scene folders.

```text
katsa . --scene exampleScene
katsa . --scene source/game/scenes/exampleScene
katsa . --scene-package dist/exampleScene.zip
```

## Settings

```lua
local Settings = {
    layoutVersion = 3,
    version = '1.0.0a',
    id = 'exampleScene',
    title = 'Example scene',
    category = 'Gameplay',
    physics = { backend = 'jolt', unitsPerMeter = 20 },
    world = { ambient = { 120, 120, 135 } },
    assets = {
        portrait = 'scene://textures/portrait.jpg',
        click = 'shared://audio/ui/click.wav',
    },
    nodes = { 'bouncePad' },
}

return Settings
```

Scene tags: `tags = { 'physics', '2d', 'game' }` in `settings.lua` lists lowercase tags. The menu shows
them under each scene title and filters by them: the search box matches title, id and tag words, and the
Tags chooser keeps the scenes that have every selected tag. A scene without `tags` shows its old `category`
as its only tag. Filtering lives in `source/game/sceneTags.lua`.

`layoutVersion = 3` does not require the category directories to exist (empty folders are lost by Git and GitHub ZIPs); it validates the five lifecycle
hooks. Version 2 archives retain their original root ui folder; archives without
a layout version retain the earlier compatibility loader. New scenes use version 3.

`version` (optional) is the engine version the scene was made for, in the form of
`source/engine/core/version.lua` (`Version.release`, written `1.0.0a`: `MAJOR.MINOR.PATCH` plus `a` alpha, `b` beta or `rc`; no letter is stable). The loader compares it with the running engine
(`Version.compatible`): a scene made for a newer engine logs a warning, an older one a note, and
`package.compatibility` holds `{ status, message, declared }` (`same`, `older`, `newer`,
`unknown`) for a launcher to show. Projects declare the same in `source/game/data/project.lua`
(`version`). A mismatch never blocks loading.

World settings apply before creation. `scene:createPhysics()` merges call-site
defaults, scene settings, then explicit launch options. `physicsBackend` overrides
`options.physics.backend`; `auto` uses the engine default with normal fallback.
Stats reports the actual solver. `kind = 'interface'` selects the camera-free host.

## main.lua lifecycle

`main.lua` exports a named module containing exactly these hooks:

| Hook | Responsibility |
| --- | --- |
| `create(scene, context)` | Construct and return state; call private builders; discover and register systems |
| `update(state, dt)` | Dispatch general system updates |
| `update3D(state, dt)` | Dispatch gameplay, physics, animation and 3D node updates |
| `update2D(state, dt, realDt)` | Update screen/world UI and dispatch 2D systems |
| `destroy(state)` | Release systems and scene-specific state |

Use the working `source/game/scenes/physics/main.lua` as a starting point. It calls
`scripts.content.new(scene)` for construction, `scene:preparePresentation()` for
common presentation setup, then `scripts.ui.interface.create(state)`. You can call any
additional private builders directly from `create`; do not add `buildUI` or other
public helper hooks to `main.lua`. Builders belong in categorized `scripts` modules, including `scripts/ui`.

A gameplay host supplies `world`, `camera`, `resources`, `audio`, `ui`, `systems`,
`settings` and `package`. The instance returned by `create` becomes `scene.demo`.

The gameplay frame order is 2D UI, input, general update, 3D update, camera/audio,
then rendering. General/3D updates use scaled simulation time; UI uses the
unscaled frame delta passed by the host. The host invokes all update hooks once.
The example `systems/simulation.lua` owns the existing content update and world
update. Physics already has an internal fixed-step accumulator: do not add a
second fixed-step loop or update the same physics/world service again in another
hook. Interface scenes dispatch the same hooks through their own main module.

## Systems controlled by scene code

The file enumeration and registration loop is visible inside each scene's
`main.lua`, not hidden in a shared loader. It scans direct `.lua` files in
`systems/` once during creation, sorts by configured order and then filename,
loads their modules and calls `create(state, scene, context, settings)`.

```lua
local systemSettings = {
    simulation = { order = 10, enabled = true },
    movement = { order = 20, enabled = true },
    ambientAudio = { order = 30, enabled = false },
}
```

Unlisted files default to order 100 and enabled. A missing `order` also defaults
to 100; extra settings fields are passed as the fourth constructor argument. Non-Lua files and
subdirectories are ignored. Put helper modules under `scripts`, not `systems`; every direct Lua file
in `systems` must export `create` and return its own instance. Configure, filter
or replace the loop directly in your scene when its loading policy differs.

```lua
local Movement = {}
Movement.__index = Movement

function Movement.create(state, scene, context, settings)
    return setmetatable({ state = state, scene = scene }, Movement)
end

function Movement:update3D(dt)
    -- Update this system's gameplay here. The simulation system owns world stepping.
end

return Movement
```

Instances may provide `start(owner)`, `update(dt)`, `update3D(dt)`,
`update2D(dt, realDt)` and `release()`. Each update phase preserves registration
order. `start` runs once when first enabled. Disabled systems receive neither
`start` nor updates, but their module and constructor are still loaded so they can
be enabled later; keep side effects in `start` when startup must be deferred.
To prevent a module from loading at all, filter it in the local registration loop.

```lua
scene.systems:setEnabled('movement', false)
scene.systems:setEnabled('movement', true)
local active = scene.systems:isEnabled('movement')
```

All registered instances, including disabled ones, release in reverse order
before world teardown. Registration belongs outside update callbacks. Use
SceneManager's deferred transitions from physics contact/query callbacks.

## Private module imports

`context:require('scripts.content')` imports from the current scene root.
Inside a private module, `require('scene.scripts.builders.object')` imports another private
module through the same package context. Its cache is local to that package
instance, so archived scenes do not accidentally resolve builtin scene files.
Engine modules use ordinary `require('source.engine...')`. Circular private
imports raise an error. Avoid hardcoded builtin scene paths in portable content.

## Custom nodes

Keep nodes used only by one scene under that scene's `nodes/`. For example,
`nightPlayer/nodes` owns `BouncePad` and `SceneButton`; `nodes/nodes` owns
`OrbitNode`. They are registered per world and do not enter the global engine
registry. Reusable engine node types remain in `source/engine/nodes`.

`settings.nodes = { 'bouncePad' }` loads `nodes/bouncePad.lua` before creation:

```lua
local BouncePad = { base = 'Mesh3D' }

function BouncePad.register(world)
    return world:registerNodeType('BouncePad', BouncePad)
end

return BouncePad
```

A definition can instead return a plain node definition; its filename becomes the
type name. Identical private names remain isolated between worlds. Engine classes
cannot be replaced by scene definitions.

### Folder nodes

A large node can be a folder. `settings.nodes = { 'vehicle' }` loads `nodes/vehicle.lua`, or, when
that file does not exist, `nodes/vehicle/init.lua`. `init.lua` assembles the node from sibling
modules that it loads with `require('scene.nodes.vehicle.model')` (any `scene.` module name works
from every file of the scene, and parts share the package's module cache):

```text
nodes/vehicle/
  init.lua          -- the node definition (base, properties, initialize, register)
  model.lua         -- deterministic driving, suspension, nitro, seats
  collision.lua     -- obstacle and car-versus-car response
  deformation.lua   -- replicable body dents
```

`multiplayerCars/nodes/vehicle` is the reference. Parts that do not touch the engine are plain Lua,
so tests can load them without a window (`validation/tests/katsa/sceneRequire.lua`).

## Assets and Image properties

`scene://` resolves from the current scene's `assets/`; `shared://` resolves from
the project asset root configured in `source/game/data/assetRoots.lua`. Ordinary
project-relative paths and manifest aliases remain supported. Images, models,
shaders and audio share these namespaces.

```lua
scene.ui:image({ image = 'shared://audio/ui/click.jpg', size = { 0, 64, 0, 64 } })
scene.audio:play('shared://audio/ui/click.wav')
scene.resources:image('portrait')
```

The image example requires an actual image at `assets/audio/ui/click.jpg`;
directory names do not determine resource type. Normalization handles separators
and `.`; `..` cannot escape a namespace. Unknown schemes and absolute asset paths
are rejected. GLTF/OBJ/MTL sidecars remain relative to the model: package them
together. Shared resources deduplicate by canonical path and import/sampler
settings; mutable model poses stay instance-owned. Resource scopes retain archive
mounts until the final lease is released.

## Scene and game archives

```text
python tools/build/packageScene.py source/game/scenes/exampleScene dist/exampleScene.zip
python tools/build/packageProject.py --output dist
```

Supported scene formats: ZIP, `.katsa`, USTAR TAR, TAR.GZ, TGZ
and 7z. Prefer ZIP for distribution. 7z supports stored, LZMA and LZMA2 data; other
formats are not supported. RAR is not portable supported input. TAR permits
regular USTAR files/directories, not links or PAX/GNU extensions.

Keep one scene root at archive root or inside one enclosing folder. Preserve
case and ordinary relative paths without an extra `./` prefix. Shared assets
come from the host project. Runtime accepts VFS-relative archive paths, external
absolute archive paths or FileData; folders are project/save-relative VFS paths.
Dropping a scene archive onto the window loads it. Scene Lua is trusted game code.

Complete game archives contain root `main.lua`, `conf.lua`, `source`, `assets`
and `vendor`. The runtime reads game ZIP/.katsa directly. For other supported formats or
a ZIP with an enclosing project folder, use the launcher:

```text
python tools/run/runProject.py --katsa katsa Game.tar.gz
```

It repacks into a temporary `.katsa` and removes it after exit. 7z packaging and
launching use bsdtar, included with current Windows. Python is only required for
these developer tools, not runtime scene loading.

## Choosing scripts or systems

`scripts` modules are imported/called explicitly; the folder contains content
builders, helpers, data and the UI code category. `systems` modules participate
in automatic scene-owned startup/update/release dispatch. A folder name alone
does not turn helper code into a scheduled system. UI construction/controllers
belong in scripts/ui; an optional dedicated UI behavior system can use them.
See [node authoring](nodeAuthoring.md) for node hooks versus scene/system hooks.

## Pause menu

`source/game/runtime/pauseMenu.lua` is the Esc menu as a module. `Game` attaches it to every scene by
default; a scene's `main.lua` can call `require('source.game.runtime.pauseMenu').attach(scene, true)`
to override it. Opening sets the time scale to 0 and closing restores the previous value; with
`keepTime = true` the time scale is never touched (hosted multiplayer keeps simulating). The menu is an
overlay inside the scene, not a separate scene, so the scene keeps updating underneath.

## Relative requires

A module can name files next to it instead of spelling the whole path, so folders can move without
editing the requires inside them:

```lua
local Heap = require('./heap')              -- same folder: heap.lua (or heap/init.lua)
local Path = require('../path')             -- one folder up
local Grid = require('../../grid.cells')    -- two folders up, then grid/cells.lua
local Nav = require('./nodes.navMap3D')       -- subfolder: nodes/navMap3D.lua
```

- `./` is the folder of the calling file, each `../` goes one folder up; the remainder is an
  ordinary dotted name. Use absolute `source.*` names for modules more than two folders away.
- Inside a scene the base is the scene root (the same tree `require('scene.…')` addresses), so a
  scene stays valid wherever it is packed. Engine modules are still required absolutely.
- Put relative requires at the top of the file. A relative name finds its caller with `debug.getinfo` on every call, so inside functions that run often use the absolute name (`source.…`, or `scene.…` in a scene).
- The caller is found from its file, so never tail-call it: write `return (require('./part'))`.
- Plugin manifests use the same form for their modules (`nodes = { NavMap3D = './nodes.navMap3D' }`),
  relative to the plugin folder.
- Implementation: `source/katsa/core/relativeRequire.lua`, installed over `require` by the host
  boot and by the standalone katsa test runner.
