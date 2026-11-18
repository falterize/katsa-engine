# Level editor scene (`levelEditor`, v108.9)

`game/scenes/levelEditor` is a map editor built **only from the engine's public API**. It touches
nothing under `source/`, `native/`, `vendor/` or `assets/shaders/engine`. Anything the engine lacks
(scene serializer, gizmos, snapping, undo, a ZIP writer) lives inside the scene.

All controls go through `InputMap` actions declared in the scene's `settings.lua`
(`input = { ... }`); the scene code never reads devices. A player (or the owner) can rebind every
editor key through the shared map. See `docs/guides/input/inputMap.md`.

## Stages

| Stage | Content | State |
| --- | --- | --- |
| a | Scene shell, fly camera, ground grid, picking and selection | in progress |
| b | Workspace tree and Properties panel | done (needs hardware check); drag-reparent is a *Move into...* button for now |
| c | Gizmos (move, rotate, scale), snapping | done except snap-to-surface; needs hardware check |
| d | Creation palette, model and image import | planned |
| e | `.katsa` location export and import | pure parts done (format, ZIP writer) |
| f | Undo/redo, copy/paste, play-test, polish | pure undo stack done |

## Module map

```text
game/scenes/levelEditor/
    settings.lua            engine settings and the editor InputMap actions
    menu-settings.lua       menu entry and tags
    main.lua                lifecycle only
    scripts/content.lua     composition: world, camera, grid, tools, UI
    scripts/core/levelOps.lua   undoable operations: create, delete, duplicate, group, ungroup,
                            reparent, rename, copy/paste, property edits (nodes addressed by EditorId)
    scripts/core/nodeData.lua   plain-data snapshots of nodes (undo of a delete, paste, export)
    scripts/core/treeModel.lua  visible rows, reparent rules, range selection (pure)
    scripts/ui/panels/tree.lua        Workspace panel
    scripts/ui/panels/properties.lua  Properties panel (rows from the engine inspector list)
    scripts/ui/theme.lua    colours and sizes (replaced by uiStyler style files in the UI stage)
    scripts/core/gizmoMath.lua  handle hit testing and rotation math (pure)
    scripts/tools/transformTool.lua  gizmo placement, drag, snapping, one undo step per drag
    scripts/view/gizmo.lua      gizmo meshes (built once, scaled to a constant screen size)
    scripts/view/meshBuilder.lua  bars, plates and rings for the gizmo parts (pure)
    scripts/core/snap.lua   snap and drag math (pure)
    scripts/core/selection.lua   ordered selection set with a primary item (pure)
    scripts/core/bounds.lua bounding sphere of a node list (pure)
    scripts/core/undo.lua   command stack with merge keys and transactions (pure)
    scripts/io/crc32.lua    CRC-32 (pure)
    scripts/io/zipWriter.lua   stored (uncompressed) ZIP writer (pure)
    scripts/io/luaText.lua  deterministic Lua table text writer (pure)
    scripts/io/locationFormat.lua   location data format, version check, encode/decode (pure)
    scripts/input/editorInput.lua   Input subclass: mouse look and viewport clicks only
    scripts/view/flyCamera.lua      fly camera driven by InputMap actions
    scripts/view/selectionBox.lua   outline over the primary selected node
    scripts/view/grid.lua   ground grid mesh
    scripts/ui/interface.lua        UI entry
    systems/simulation.lua  per-frame loop
```

"Pure" modules do not use `katsa`, `ffi` or any engine service, so they run in plain Lua and are
tested directly (`validation/tests/versions/v108_9/levelEditorLogic.lua`).

## Controls (InputMap actions)

| Action | Default binding |
| --- | --- |
| `editorLook` | hold right mouse button (captures the mouse) |
| `editorForward/Back/Left/Right` | `W A S D` while looking |
| `editorUp/Down` | `E` / `Q` while looking |
| `editorFast` | `Shift` |
| `editorSpeedUp/Down` | mouse wheel while looking |
| `editorPick` | left mouse button |
| `editorAdd` | `Ctrl` (add to selection) |
| `editorRange` | `Shift` (range select) |
| `editorFocus` / `editorFrameAll` | `F` / `Home` |
| `editorToolSelect/Move/Rotate/Scale` | `Q W E R` (not while looking) |
| `editorToggleGrid` | `G` |
| `editorUndo/Redo` | `Ctrl+Z` / `Ctrl+Y` |
| `editorDuplicate/Copy/Paste/Delete` | `Ctrl+D` / `Ctrl+C` / `Ctrl+V` / `Delete` |
| `editorSave/Open` | `Ctrl+S` / `Ctrl+O` |

## Content creation and import (stage d)

- `scripts/builders/catalog.lua` lists the Create tab items. Each item builds itself through `ops:create` (one undo step) at `content:placement()`: the view centre meets the ground plane `y = 0` (otherwise eight units ahead), snapped to the move step.
- Cylinder and cone are meshes made by `builders/shapes.lua` (24 segments, outward normals) and marked with the `EditorShape` attribute so undo, duplicate and export rebuild them.
- Trigger and Collider create a `Body3D` (Static) with a `Collider3D` (`isTrigger` for triggers) and a translucent box so they can be seen and picked.
- The Files tab uses `katsa.filesystem`. `io/assetStore.lua` copies a chosen file to `editor/assets/models|textures/` in the save directory (unique, safe names); the same path without `editor/` is used inside the exported package. Models remember their file in the `EditorModel` attribute; images become sprite quads or the colour map of the selected mesh.
- Dropped files are not used for import: the engine's `katsa.filedropped` switches scenes.

## `.katsa` location format

A location is a **ZIP archive** (the engine reads ZIP; the scene writes it with its own stored
writer) that is also a valid Katsa scene package:

```text
settings.lua          engine settings of the location (plain table)
main.lua              tiny loader: reads assets/location.lua and builds the nodes
assets/location.lua   the serialized tree (see below)
assets/models/...     copied models
assets/textures/...   copied images
```

`assets/location.lua` returns:

```lua
return {
    format = 'katsa-location',
    version = 1,
    nodes = {
        {
            class = 'Mesh3D',
            name = 'Floor',
            properties = { position = { 0, 0, 0 }, size = { 20, 1, 20 } },
            children = { },
        },
    },
}
```

Rules: paths inside `properties` that point to package files are relative to the package root
(`assets/textures/brick.png`); node references are stored as `{ ref = 'Parent/Child' }` paths;
unknown versions fail with `Unsupported location version N (this editor reads 1)`.

## Engine APIs reused

`world:create`, `Camera3D` (`screenRay`, `project`, `pixelsPerUnitAt`), `Picking.raycast`,
`Mesh3D`/`Geometry.mesh`, `Clone.collect` and the inspector schema (`Schema.keys`, `descriptor`,
`options`), `katsa.filesystem`, `source/katsa/core/archive.lua` (reader), the model importer
registry, `SurfaceAppearance3D`, `ScrollFrame`, `TextBox`, `ui/widgets/collapsible`, uiStyler
style files.

## Not serialized (kept honest)

Runtime caches, signal connections, scripts attached by code, physics state, anything the
inspector schema does not list. The exact list is kept next to the serializer once stage e lands.

## Gizmo notes and limits

* Handles are tested geometrically against the mouse ray (not by mesh picking); the gizmo keeps
  `Gizmo.PIXELS` (120) radius on screen through `camera:pixelsPerUnitAt`.
* The gizmo meshes are depth-tested: a handle inside a large object can be partly hidden, though
  it still picks. Drawing it on top needs a shader the engine's `render_mode` list cannot express
  yet (no depth-test-off mode), so it is left for later.
* Snapping: `Snap` toolbar button; holding Ctrl inverts it. Move snaps to world grid coordinates
  in World space and to relative steps in Local space; rotation and scale use the steps from
  `settings.editor.snap`. Snap-to-surface is not implemented yet.
* Edited nodes are assumed to have translation-only parents (true for the Level and editor groups).
