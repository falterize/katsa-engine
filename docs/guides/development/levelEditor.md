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
| f | Undo/redo, copy/paste, polish | pure undo stack done |

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
| `editorDuplicate/Cut/Copy/Paste/Delete` | `Ctrl+D` (Clone) / `Ctrl+X` / `Ctrl+C` / `Ctrl+V` / `Delete` |
| `editorSave/Open` | `Ctrl+S` / `Ctrl+O` |

## Content creation and import (stage d)

- `scripts/builders/catalog.lua` lists the Create menu items. Each item builds itself through `ops:create` (one undo step) at `content:placement()`: the view centre meets the ground plane `y = 0` (otherwise eight units ahead), snapped to the move step.
- Cylinder and cone are meshes made by `builders/shapes.lua` (24 segments, outward normals) and marked with the `EditorShape` attribute so undo, duplicate and export rebuild them.
- Trigger and Collider create a `Body3D` (Static) with a `Collider3D` (`isTrigger` for triggers) and a translucent box so they can be seen and picked.
- The Files tab uses `katsa.filesystem`. `io/assetStore.lua` copies a chosen file to `editor/assets/models|textures/` in the save directory (unique, safe names); the same path without `editor/` is used inside the exported package. Models remember their file in the `EditorModel` attribute; images become sprite quads or the colour map of the selected mesh.
- Dropped files are not used for import: the engine's `katsa.filedropped` switches scenes.

## Interface (Godot-style docks)

- Layout (`ui/support/layout.lua`, pure): toolbar on top, **Workspace** (left) and **Properties** (right) over the full middle height, a bottom dock with tabs (**Assets**, **Locations**) under the viewport, a status bar. The three borders are draggable splitters (`ui/support/dock.lua`); sizes are clamped so the viewport never drops below 300x160, and the chosen sizes are saved.
- Nothing runs off the screen: the toolbar and the Create palette wrap onto more rows through `ui/flow.lua` when the window or dock is narrow.
- **Menu bar** (`ui/support/menus.lua`, `panels/menubar.lua`): *File* (New, Open, recent files, Save, Save as, **Import .katsa** adds a file's objects to the level as one undo step, **Export .katsa** writes `editor/exports/<name>.katsa`), *Edit* (undo/redo, copy/paste, duplicate, delete, select all, group), *Create* (everything from the palette), *View* (grid, light/camera gizmos, shadows, wireframe, frame, reset layout) and *Settings* (editor settings, shortcuts, theme). Items show their InputMap shortcut and check marks.
- Tool strip: Undo / Redo, Select / Move / Rotate / Scale, World/Local and Center/Origin, **Snap** with three editable steps (move in units, rotate in degrees, scale), **Surface** snap (a free Move drag puts the object on the surface under the pointer; Ctrl inverts), Grid and . Active toggles are highlighted.
- Selection: click, Ctrl-click, drag a **rectangle** in the viewport (objects whose centre falls inside are taken), Ctrl+A.
- Properties are grouped into collapsible categories (`ui/propertyGroups.lua`): Transform, Appearance, Light, Camera, Physics open; Node, Rendering (draw cutoff `maxDistance`, `onTop`, ...) and Other collapsed. Editor-created meshes get `maxDistance = 0` (never culled by distance).
- **Assets** (bottom dock, `io/levelFiles.lua`, `core/importer.lua`): one browser with no mode switch. Its first screen offers *Level files* (the level's own folder, `editor/assets` in the save directory, shown as `assets/`) and *Project assets* (the project's `assets/` folder, read-only). In Level files: **Import...** (system file dialog, any file type; also the ribbon Import button, the File menu and dropping files on the window) copies into the folder on screen, then reveals the new file and says where it went; an import never places anything in the scene. New folder, New file, Rename and Delete (confirm by typing `yes`) manage the folder; **Add to level** places the selected model (or an image as a sprite quad); right-click gives the same plus Use as texture. Project assets can be used in place (`shared://`, nothing copied) or copied into the level files. Names cannot contain separators or `..`, so nothing can leave the folder. Renaming or deleting a file does not rewrite objects that use it: they show the placeholder until re-assigned.
- **Touch** (`input/pointer.lua`, `panels/touchControls.lua`, pure geometry in `ui/support/touchLayout.lua`): every panel and the viewport read one pointer, which is the mouse or the first finger acting as the left button; holding still for half a second is a right click (context menu). On-screen controls fly the camera: a move stick (forward/back/strafe), a look stick, Up, Down and Fast. A finger that lands on a control belongs to it, other fingers act as the mouse. Two fingers in the viewport select a zone: rest one finger, put a second one down and spread them; the two points are opposite corners and lifting a finger selects everything inside (a drag on a gizmo handle is not interrupted). Settings > Touch: show controls Auto (phones, tablets, or after the first touch) / Always / Never, look stick speed, **Edit layout** (drag a control to move it, Smaller/Larger resize the selected one, Reset) saved with the preferences. Positions are fractions of the viewport, so they follow the dock sizes.
- **Performance info**: View > Performance info shows, in the status bar, the average milliseconds the editor spends per frame in each of its own parts (fly camera, gizmo, outlines, lights, every panel). Use it when the frame rate drops: it tells which part is slow.
- **Create**: `Shift+A` (action `editorCreate`), the **+** button in the Workspace header and the Create menu open one searchable list (type to filter, Enter creates the first match). From `Shift+A` over the viewport and from the viewport context menu the object is placed under the pointer.
- **Context menus** (right button, one shared pop-up, `panels/popup.lua`): on an object in the viewport or a Workspace row (Cut, Copy, Paste into, Clone, Delete, Rename, Hide, Lock, Group, Ungroup, Frame), on empty space in either (Paste, Select all, Frame all and the Create list), on a file or folder row of the Level files (add to level, use as texture, Cut / Copy / Paste / Clone / Move to / Rename / Delete; a row can also be dragged onto a folder row or `..` to move it) and on a location row (Open, Import). In the viewport a short right click opens the menu; holding the button and moving is still the fly-look.
- **Light visualisation** (`scripts/view/lightViz.lua`): every light has a small tinted marker (rings for a point light, a cone stub for a spot, rays for the sun) drawn on top of the scene; click the marker to select the light. The selected light also shows its reach: three range circles (point), the cone to `range` with `radius` (spot), an arrow and ring along the direction (sun). The shapes live outside the level, so they are never saved or undone. View > Light gizmos toggles them; the engine's own line gizmos are switched off in this scene.
- Multi-selection: every selected object has its own outline (the primary one, which carries the gizmo, is orange, the others pale yellow).
- Workspace: select (Ctrl adds, Shift ranges; the pointer is polled, not tied to widget signals), **drag over rows or over the empty space under them to select the rows crossed** (Ctrl keeps the old selection), plain drag on a row moves it, show/hide, lock, Duplicate / Delete / Group / Ungroup, and **drag and drop**: drop on the middle of a row to move inside it, on the upper or lower quarter to place before or after it (a frame or a line shows the target; one undo step; undo restores parent and order).
- Gizmos and the selection outline draw **on top of everything** (`assets/shaders/onTop.glsl`, a scene `Shader3D` that squeezes the clip depth), so they stay usable inside large objects. Picking handles geometrically, so it is unaffected.
- **Settings window** (toolbar): Appearance (dark/light theme through the uiStyler plugin), Interface (dock sizes, reset), Snap & Grid, Camera (fly speed, look sensitivity, FOV) and Shortcuts: **Rebind** any editor InputMap action (a modifier first makes a chord, Esc cancels) or **Reset** it. Everything is stored in `editor/settings.lua`.
- Styling: widgets carry tags (`dock`, `bar`, `tool`, `row`, `selected`, `on`, `field`, `list`, ...); `assets/styles/editor.lua` maps them to theme tokens, so a theme switch restyles the whole editor. Helpers are in `ui/support/kit.lua`.
- The 3D view is a **ViewportFrame** with its own World3D and camera (`content.world`, `content.camera`), sized by the dock layout; the scene's main World3D stays empty and only carries the UI. Pointer positions are converted to viewport pixels (`content:viewportPoint`) before picking and gizmo drags, so the camera centre is the viewport centre and clicks on panels never reach the 3D view.
- Known limits: the Workspace does not auto-scroll while dragging near its edges; a rebind replaces all bindings of the action.

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

Each node entry also carries `attributes` (editor markers such as `EditorShape`, `EditorLocked`,
`SpawnPoint`; never the runtime `EditorId`) and, for an imported model, `model` (its file) instead
of its meshes. The top level may hold `camera = { position, rotation, fov }`.

Rules: paths inside `properties` and `model` that point to package files are relative to the
package root (`assets/textures/brick.png`); while editing they live under `editor/assets/` in the
save directory and are rewritten both ways. Unknown versions fail with
`Unsupported location version N (this editor reads 1)`; a bad file leaves the open location
untouched.

### Save, open, autosave

- **Ctrl+S** saves to `editor/locations/<name>.katsa` in the save directory (name from the
  Location tab, default `untitled`); **Ctrl+O** opens the most recent file. The Location tab also
  lists recent files, the autosave and every saved location, with Save and New.
- Autosave writes `editor/autosave.katsa` every `editor.autosaveSeconds` (60) when the undo
  version changed. The recent list is `editor/recent.lua`.
- The package carries its own `scripts/loader.lua` (source: `scripts/package/loader.lua`), plus
  `scripts/shapes.lua` and `scripts/luaText.lua`, so it runs as a scene without the editor.

## Engine APIs reused

`world:create`, `Camera3D` (`screenRay`, `project`, `pixelsPerUnitAt`), `Picking.raycast`,
`Mesh3D`/`Geometry.mesh`, `Clone.collect` and the inspector schema (`Schema.keys`, `descriptor`,
`options`), `katsa.filesystem`, `source/katsa/core/archive.lua` (reader), the model importer
registry, `SurfaceAppearance3D`, `ScrollFrame`, `TextBox`, `ui/widgets/collapsible`, uiStyler
style files.

## Not serialized (kept honest)

Runtime caches, signal connections, scripts attached by code, physics state, anything the
inspector schema does not list, node-reference properties and attributes (`isAttributeReference`),
values that are not plain data (functions, userdata, NaN; each export reports how many were
dropped), and the editor's own sun, grid and gizmos. An imported model copies only the chosen
file: companion files of a glTF (`.bin`, textures) are not copied yet, so prefer `.glb`.
Lights, the sun and ambient colour of the editor are not exported; the package loader adds a
default sun when the level has no directional light.

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

## Toolbar details

- Pixel icons are drawn in code (`scripts/ui/widgets/icons.lua`, 16x16 ASCII art, tinted by the style sheet).
- Hovering a toolbar button shows a hint in the status bar.
- Grid: `Cell` (unit size), `Major` (bright line every N cells) and `Size` (cells covered each way) are editable and saved in the preferences.

## Ribbon, tooltips and asset targets

- The ribbon (`panels/toolbar.lua`) has four tabs: **Home** (undo, tools, space/pivot, snapping), **Create** (create list, lights, import), **View** (grid cell/major/extent, light markers, shadows, wireframe, frame) and **Assets**.
- `panels/tooltip.lua`: any widget registers a description; it appears after the pointer rests on it. Property names use the engine hint texts (`editor/hints`).
- Assets: imports are copied into `editor/assets/` (written into the package as `assets/...`); project files used in place are stored as `shared://<path under assets/>`.

## Importing and visual nodes

- **Import** (Create and Assets tabs, Create menu, file browser) calls `katsa.system.openFileDialog`; several files can be picked. Without a native dialog (no zenity/kdialog) the editor says so and opens the file browser; dropping files on the window always works.
- `core/importer.lua`: models are placed, images become sprite quads (or the colour map of the selected mesh from the browser), other files are copied to `editor/assets/{audio,fonts,files}` and reported.
- **Create > Visual**: Billboard, Surface UI, Decal, Surface appearance, Particles, Attachment. The text of a Billboard/Surface UI is the `EditorText` attribute (inspector row `text`); the label inside the board is rebuilt from it on load.

## Level files, texture target and drag feedback

- The level files (`editor/assets`) belong to the open level: they are emptied when the editor starts, on File > New (example or empty) and when a location is opened (the opened package brings its own files). Save packs the referenced assets into the `.katsa`, so nothing is lost for saved work.
- "Use as texture of the selection" works on a selected Mesh3D (colour map through `SurfaceAppearance3D`) and on a selected Decal3D (its `image`).
- Dragging a file in the Level files tab highlights the folder it would move into and shows a label with its name at the pointer, like the Workspace drop marks.
- The scene's own (empty) World3D is rendered at the lowest density without a sky, so full-screen passes are spent only on the editor view. Probe: `--test-v108.9.editor` (per-stage frame cost; software GL, so relative numbers only).
