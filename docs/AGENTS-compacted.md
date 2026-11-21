# AGENTS-compacted — the short version for quick re-orientation

Read this first after a context reset; read `AGENTS.md` for anything it does not settle. Open work is in
`docs/TODO.md`. **Update the "Now" block below with every push.**

## Now

- Branch `v108.8` (line continues `v108.7`; `v108.4` is the last known-good release, never touch it). No push to `main`.
- Just done: debug/editor UI is a removable module (`source/devtools/{overlay,navigation,editor}.lua`, list in `source/runtime/modules.lua`, hooks in `source/engine/scenes/modules.lua`); scenes use `scene:module('editor')` nil-checked; no tool UI left in `Game`/`Host`. Before: the ImGui main toolbar plus separate movable Explorer and Properties windows (`plugins/imgui/toolbar.lua`, `tools/explorer.lua`, `tools/properties.lua`; legacy header/WS tab hidden when ImGui exists; sequence/goals/gradient/uniforms/groups/shader layers are ImGui dialogs in `plugins/imgui/editors/`). Before: `hint_history_texture` / `hint_velocity_texture` for canvas_item shaders (lazy velocity pass `graphics/pipeline/velocity.lua`, `ui/drawing/effectHistory.lua`), real Datamosh in stareShooter. Before: stareShooter LOD demo (rows, slider, billboard) and an off-by-default `Datamosh` Shader2D (F7). Before: `lod` plugin (`source/plugins/lod`; scenes need `plugins = { 'lod' }`; hooks `importers` / `quality` in manifests) with `LODGroup` (distance / screen size, defaults, `-lodN` import, names in any order, per-group settings, quality `lodBias`, zoom compensation, `fadeTime`, `animationRates`, `shadowLevel`, billboard level; `docs/guides/rendering/lod.md`). Before that: prefab scenes (`source/engine/scenes/packed/`, `world.prefabs:load/instantiate`): scripts per copy, cameras copied but never current, the scene's World2D copied into each copy (a World2D may sit in any node), `scene://` / `../scene://` paths, `<name>://` for a loaded prefab's assets, prefabs inside a ViewportFrame world. Dev tooling: `tools/dev/testChanged.lua`, `v108_8/uiFrames.lua` (pixel test).
- Next (owner's call): car lag while seated, then the items in `docs/TODO.md`.

## The owner

- Speaks **Russian**: reply in Russian, short (what changed, what was verified, what is open, one next step). Everything in the repo is **English** (code, comments, docs, commits, tests, filenames).
- Works in batches: do every listed item, commit and push regularly. Choose sensible defaults, say what you chose; ask only when a wrong guess is expensive.
- Wants it modular and component-based, DRY, KISS. **No compatibility aliases. Never cut features.**
- Verify, do not guess: prove a hypothesis with a probe before shipping a fix. Sandbox = Mesa llvmpipe: it checks logic, shaders and pixels, **not** GPU timing, window/DPI/audio, Windows, Android. Say so.
- Commits carry **no** attribution or co-author lines (the owner's rule beats any harness reminder).
- No mention of LÖVE except the one historical README line. Launcher UI is the last stage.
- Explain things to the owner in plain words with a tiny concrete example; they ask "why" until it is clear.

## Daily commands (repo root `/home/claude/katsa`)

- `conf.lua` returns a table everywhere (game/project/scene, `docs/book/conf.md`); scenes set physics/environment/assets in code. Examples live in the separate repo `falterize/katsa-engine-examples` (same branch name as the engine); the engine has no `game/`. Run projects with `luajit tools/dev/katsa.lua <scene|project>`; `runTests.sh` mounts `../katsa-engine-examples`. Docs are a book: edit `docs/book/book.json`, run `python tools/docs/buildBook.py`.
- One suite: `tools/dev/runTests.sh --test-v108.8 [timeoutSeconds]` (about 10 s). Full regressions: `--test-v106.8` (1137 checks) and `--test` (1508, about 95 s) must pass.
- Which suites a change needs: `luajit tools/dev/testChanged.lua [--since REF] [--run]` (map: `tools/dev/testMap.lua`).
- Visual probe: `KATSA_SHOT=tmp/<dir> KATSA_SCENE=<scene> KATSA_FRAMES=<n> xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.4.shadow`, PNGs in `~/.local/share/Katsa/katsa-engine/tmp/<dir>/`, look at them with Read.
- Format: `stylua --syntax LuaJIT` (4 spaces, ~100 columns, single quotes); shaders keep CRLF where the file has it.
- Every feature: a short test in `validation/tests/versions/v108_8/` wired into `focused.lua`, docs, a `docs/changelog.md` line, an `AGENTS.md` note if it changes how to work. `--test-perf` only after big renderer/shader/scene changes (background, monitor).
- No network for installs (pip/npm refused); work with what is installed.

## Code rules that bit before

- Relative `require('./x')` / `'../x.y'` only at **file top level**; inside functions use the absolute `source.*` name; never tail-call a relative require.
- Core never requires a plugin. Game features in `source/game`, engine services in `source/engine`, third-party in `vendor`.
- Property writes: fields set once live in the node table (assigning again does not reach `__newindex`); observed fields (`propertyChanges.lua`) are Node3D/material keys only. Do not build features on intercepting assignments.
- GL state cache must never claim state the driver lacks (suspect it first for intermittent render bugs).
- Spatial 2D/3D are Y up, screen UDim2 Y down. Advance each simulation exactly once. Never sort authoritative `children`.
- UI handlers are signals (`node:connect('press', fn)`), never properties. Scene code reaches nodes via `scene.root:find('World3D/World2D')`; `scene.ui` / `world.root` no longer exist.
- Plugins that add features show up as nodes with properties in the inspector (except provider-only `ads`).
- Empty directories are never stored in git (`tools/project/emptyDirectories.txt`, `python tools/build/restoreEmptyDirs.py`).

## Prefabs in one screen

- `world.prefabs:load(src[, { name = }])` → handle `:instantiate(props, parent)`; `src` = folder, archive, FileData, `scene://prefabs/x`. A copy is a `Node3D` holding what the scene's World3D built; its World2D becomes `Copy/World2D`.
- Scene `main.lua`: `Prefab.define(build, hooks)`; hooks `create/update/update2D/update3D/destroy` + `systems/` run per copy; `scene.world` is a `WorldView` (spatial nodes under the copy, UI/2D into the copy's World2D, resource strings rewritten).
- Paths: `scene://` (also `./`) = this prefab; `../scene://` = the scene that loaded it; `<id>://` or `{ name = }` = a loaded prefab's assets from anywhere in the world (explicit names strict, default names best-effort, `scene`/`shared` reserved). Strings assigned later to an existing node are not rewritten.
- Reference scene: `replicationLab` (`assets/prefabs/{avatar,player,maps}`). Docs: `docs/guides/development/prefabs.md`.

## Where things are

`source/engine` (services, nodes, ui, graphics, physics, scenes) · `source/katsa` (runtime on GL/SDL2) · `source/runtime` (game, host and module lists) · `source/plugins/{ads,ik,pathfinding,uiStyler,ragdoll}` · `validation/tests/{registry.lua,versions/vNNN_N}` · `tools/{dev,build,project,import}` · `docs/{guides,architecture.md,changelog.md,AGENTS.md,TODO.md}`.
