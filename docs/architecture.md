# Project architecture

The dependency direction is game → engine → vendor. Engine services do not depend on examples. Third-party source and binaries stay in `vendor`; project adapters stay in the engine. Entry points are `conf.lua` and `main.lua`.

## Runtime categories

| Area | Responsibilities |
| --- | --- |
| `engine/core` | Scene stack, time, resource scopes, groups, snapshots and class assembly |
| `engine/nodes`, `engine/world` | Node types, hierarchy, lifetime, transforms and scene collections |
| `engine/graphics`, `lighting`, `materials`, `shaders` | Render preparation, batching, quality, lighting, shadows and shader composition |
| `engine/physics` | Common body API, fixed steps, queries, sensors, constraints and separate backend adapters |
| `engine/animation`, `engine/import` | Animation, skeletal pose/skinning and asset loading |
| `engine/ui`, `input`, `audio`, `particles` | Layout/drawing, routing, sound and effects |
| `engine/editor` | Runtime Workspace tree, inspectors, curves and panels |
| `engine/scenes` | Package loading, archive mounts, resource namespaces and named systems |
| `game/scenes` | Scene packages with settings, main entry points and private assets/scripts |
| `game/runtime` | Common gameplay host, update/draw phases, input and overlays |
| `game/ui`, `game/data` | Common Stats adapter, resource manifest, startup scene and defaults |

Named Lua modules use the same shape: imports, local bindings, a module table, private helpers, named functions, and the final table export. Factories expose `create`/`new`; example builders expose `build`; class installers expose `install`; node registration uses `register`. Stateful methods use `:` and stateless helpers use `.`. These roles share the same source layout.

Oimo and Jolt use sibling modules for bodies, colliders, contacts and constraints. Modules export method tables, and drivers assemble them explicitly with `core.extensions.apply`. Native dependencies are imported in the module that uses them; positional dependency-injection wrappers are not used. Native callbacks retain their JIT/lifetime safeguards.

The renderer, UI and other multi-part classes use explicit named `install` methods when wiring requires several class types. Installation happens once when a module loads. Regular callbacks and reader closures remain functions because their runtime purpose requires a function value.

## Ownership and update flow

SceneManager owns scene lifetime and safe transitions. Resource scopes release Canvas/Mesh/Shader/audio objects. Worlds own node collections and their physics services. Fixed-step simulation is independent of rendering frequency. Public mutable values remain observable through snapshots and revisions; cache optimizations must preserve in-place edits.

Scene packages use `settings.lua` for engine configuration (physics, world, plugins, nodes, frame rate), `menu-settings.lua` for what only launchers read (id, title, category, tags) and `main.lua` for
creation, general/3D/2D updates and destruction only. Private builders and nodes
live inside each scene; all category folders are present. System discovery,
ordering and startup are explicit loops inside that scene's `main.lua`. Systems are
released before world teardown. Asset scopes retain archive mounts until all
leases finish; normalized final paths preserve shared-resource deduplication.
See the [scene authoring guide](guides/development/scenes.md).

Rendering prepares visibility, appearance, lights and shadows, then draws opaque/transparent/debug passes and screen UI. ViewportFrame has an independent world and renderer. Physics defers mutation during queries/contact traversal and releases bodies before native world handles. See [physics details](guides/physics/backends.md).

Current guides are grouped by feature under `docs/guides`. The release README, validation reports and migration notes stay beside `source` in the version directory, so the `.katsa` archive contains current project documentation rather than historical release notes.

## Scene implementation layout

A scene's `scripts/content.lua` composes its content. Private helpers are grouped
under builders, behaviors, lighting, animation, data or catalog only when needed.
The UI entry remains in `scripts/ui/interface.lua` (or `scripts/ui/controller.lua` for interface
scenes); supporting modules are categorized under UI panels, previews, examples
and world-space UI. Executable systems remain directly under `systems/`, with
startup ordering and settings visible in `main.lua`.

Both packers preserve empty directories explicitly. TAR-to-ZIP conversion also
retains directory records, including marker-free scene asset categories.

Scene layout version 3 places the complete scene UI code category in scripts/ui.
Version 2 packages keep their previous root ui directory and remain supported.
The UI library in engine/ui and the common game Stats adapter remain shared
services. scripts modules run when imported/called; systems modules are registered
with scene lifecycle dispatch. Node lifecycle hooks are a separate instance API.

## Application startup and persistent data

The root main file installs `engine/scenes/bootstrap.lua`, which owns the katsa
callbacks once. Collection-specific startup is an adapter in `game/runtime/startup.lua`;
standalone games use the default scene host. Both project types share
`engine/core/windowConfig.lua` through a minimal conf wrapper. Project metadata
lives in `game/data/project.lua`. Generator resources belong under tools/project.

`engine/persistence/data.lua` is the scene-facing read/write facade. Hierarchical
scopes select saves directories. `formats.lua` selects JSON or original-byte
handling, `store.lua` handles schema/checksummed documents, `files.lua` handles raw
files/streaming and legacy raw locations, and `fileIO.lua` shares publication and
bounded copying. The optional settings wrapper is kept for compatibility; game
preferences can be ordinary tables. No persistence work runs automatically per frame.

## Physics dimensions

`source/engine/physics/2d` owns Box2D bodies, fixtures, queries, contacts, joints,
geometry builders, fixed stepping and debug drawing. `source/engine/physics/3d`
owns the existing 3D facade with sibling `backends/oimo` and `backends/jolt`.
`physics/init.lua` preserves the public 3D entry point. New code can explicitly
require `source.engine.physics.2d` or `source.engine.physics.3d`.

Physical nodes are categorized under `nodes/physics/2d` and `nodes/physics/3d`.
Dimension-specific class names retain their `2D`/`3D` suffix. The scene module
boundary redirects archived scenes' earlier 3D import paths, without duplicating
implementation files in the root physics folder.

World2D retains its screen-UI role and optionally owns a Physics2D and Camera2D.
Spatial 2D nodes use rigid transforms in logical world units, separately from
UDim2 widget layout. Camera2D transforms physics rendering; HUD widgets stay in
screen space. Camera tracking is immediate, without built-in smoothing.

`UI:update(realDelta, simulationDelta)` keeps responsive UI wall time separate
from scaled physics time. Scene main modules pass both values; custom systems
can disable automatic 2D stepping through `autoUpdatePhysics = false`. Contact
callbacks are queued until Box2D unlocks. Worlds, nodes and dependent joints own
and release their native resources explicitly. Box2D's global meter is never
changed per scene; per-world conversion permits different units concurrently.

See [2D physics](guides/physics/physics2D.md) and
[editable collider geometry](guides/physics/pointColliders.md).

World2D clocks do not inherit their enclosing World3D timeScale. The application
simulation delta fans out before either local multiplier. UI animation time,
2D fixed stepping and processed scripts use the owning World2D clock; spatial
3D processing uses its World3D clock. NodeTree registrations remember their
clock owner and refresh it on reparenting. Nested viewport worlds establish
another independent clock boundary. The application-wide manager multiplier is
still available as a separately labeled override.

The new physics examples use the same collection runtime, Workspace, navigation,
Tools and Debug as existing scenes. Their main modules conditionally call the
presentation adapter, allowing the same scene folders to run in a minimal
standalone Host when exported to an independent game.

## Spatial 2D authoring

Node2D and Node3D represent transform groups; World3D itself defines fixed coordinates.
The 2D authoring path is World2D -> Node2D -> Body2D -> Collider2D -> UI visual.
`ui/spatial/plane.lua` handles affine surfaces and inverse pointer transforms; the physics
renderer draws debug geometry only. `ui/layout/order.lua` stores presentation order
without sorting the public hierarchy. World2D opacity is composed once through the
existing UI compositor. Both world types use `world/gravity.lua` for independent scalar
magnitude/direction controls and compatibility with legacy solver vector settings.

Spatial 2D uses Y up, with projection and local UI conversion at the rendering/input
boundary. `world/visibilityLayers.lua` shares named visual-layer policy across HUD,
spatial UI and 3D material contributions. Scene systems own example physics updates;
`graphics/debug/orientation.lua` draws optional camera-relative axis overlays in both
collection and minimal hosts. The scene-owned 2D runner uses `animation/flipbook.lua`
for its eight-frame 8x8 player atlas.
