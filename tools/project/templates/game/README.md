# My Game

A standalone game project built with Katsa.

Run `katsa .`. The start scene displays a rotating cube, saved score and a saved
rotation preference. Press F3 to inspect Stats and export recent metric history.

- Configure title, unique save identity and first scene in `source/game/data/project.lua`.
- Configure `frameRateLimit` in `source/game/scenes/start/settings.lua`: `0` is
  uncapped and a positive integer is an optional ceiling. VSync stays off.
- Compose content in `source/game/scenes/start/scripts/content.lua`.
- Configure systems directly in the scene's lifecycle-only `main.lua`.
- Keep UI code in `scripts/ui`, custom nodes in `nodes`, and scene assets in `assets`.
- Use `scene://...` for local assets and `shared://...` for the shared `assets` folder.
- Use `local data = scene.data:scope('game')`, then
  `data:write('progress.json', progress)` and `data:read('progress.json')`.
  Preferences are ordinary tables too; text/binary files retain original bytes.
- Run `katsa . --smoke-test` for ten startup/render frames.
- Build a `.katsa` with `python tools/build/packageProject.py --output dist`.

Scene hooks are `create`, `update`, `update3D`, `update2D`, and `destroy`. Systems
are discovered and ordered by the scene's own `main.lua`. A disabled system does
not update; the host does not run hidden simulation steps. Saving nodes, native
objects, functions or an entire live scene is not supported by the data-save API.

The application owns its save directory. Named JSON saves keep a verified backup; report read errors instead of silently resetting player progress.
Run only one writer per save slot. The example collection's full guides and tests
remain in the original engine distribution.

Project code is MIT; see LICENSE and retained notices in `vendor`.

All scenes expose `scene.data`. Use named scopes for shared progress/preferences
and read/write/openFile for tables, text, binary and streaming data. Files live
in the device's save directory outside the replaceable game folder. Keep
`source/game/data/project.lua.identity` stable across updates; schema changes use migrations.
