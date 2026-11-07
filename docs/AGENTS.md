# AGENTS.md — instructions for AI agents working on Katsa

Katsa is an open source 2D/3D engine on its own **LuaJIT + OpenGL** runtime (SDL2 platform layer, `katsa.*` API). It was migrated from LÖVE, which is history now. Repository: `falterize/katsa-engine`. Read this file fully before changing anything; the rules below come from real regressions.

Sections: 1 Working with the owner · 2 Repository map · 3 Code style · 4 Modules and requires · 5 Build, run, test · 6 Git and releases · 7 Rendering and GL · 8 Nodes, worlds, physics · 9 UI (ScrollFrame, uiStyler, widgets) · 10 Animation and IK · 11 Plugins · 12 Scenes and the collection runtime · 13 Multiplayer and multiplayerCars · 14 Assets, XML, images · 15 Sandbox pitfalls · 16 Open items.

---

## 1. Working with the owner

- The owner speaks **Russian**. Reply to them in Russian. Everything written to the repository is **English**: code, comments, docs, test names, commit messages, filenames, user-facing strings. No exceptions.
- Do not mention LÖVE anywhere except the single historical line in `README.md`.
- Ask questions only when a wrong guess is expensive or the request is truly ambiguous. Otherwise choose the sensible default, say what you chose, and continue. "Do you have questions?" from the owner is an invitation, not an obligation.
- Work in **batches**: when the owner lists several items, do all of them in one go instead of finishing one and stopping. Commit and push regularly.
- Never cut functionality ("функционал движка не урезай"). Fix or improve; do not delete features to make a problem disappear. Performance work must keep every feature (e.g. quality profiles reduce cost, they do not remove effects).
- The **launcher UI is the LAST stage** of the plan. Do not start it until the owner says so.
- Verify instead of guessing. Earlier misdiagnoses (shadow flicker blamed on cascades, acne and the normal matrix) cost the owner many test rounds; the real cause was GL state (see 7). When a diagnosis is a hypothesis, prove it with a probe before shipping a "fix", and say plainly when something can only be verified on real hardware.
- The sandbox renders with Mesa llvmpipe (software GL): it validates logic, shaders and images, **not** real-GPU timing, window/DPI/audio behaviour, the Windows .exe or Android. The owner verifies those. Say so when relevant.
- Keep final answers short: what changed, what was verified, what is still open, one natural next step.
- Plugins that add something (nodes, features) must be visible as **nodes with properties** in the inspector, except pure provider plugins such as `ads`. The IK plugin is the model: `InverseKinematics3D`.

## 2. Repository map

| Path | Content |
| --- | --- |
| `source/engine/` | Reusable engine services and node APIs (nodes, ui, graphics, physics, animation, editor, input, net, world ...) |
| `source/engine/components/` | Shared property groups of nodes (image, lighting, shadowing, layering, renderRange, brightness, tint): one definition per rule |
| `source/engine/graphics/{materials,shaders,lighting}` | Material resolution, shader layers and shader source loading, light orientation defaults |
| `source/katsa/` | The runtime layer: graphics on GL, window, audio, filesystem, net, platform |
| `source/game/` | Scenes (`scenes/<name>`), the common collection runtime, game data (`data/project.lua`), `sceneCatalog.lua` |
| `source/plugins/<name>/` | Optional features: `ads`, `ik`, `pathfinding`, `uiStyler` |
| `assets/` | Shared models, textures, shaders (`assets/shaders/engine/*.glsl`), audio, fonts |
| `validation/tests/` | **All** tests; versioned suites in `validation/tests/versions/vNNN/`, registry in `validation/tests/registry.lua` |
| `native/`, `vendor/` | Project C/C++ sources / pinned third-party code (never hand-format vendor code) |
| `tools/` | `dev/katsa.lua` (dev host), `dev/runTests.sh`, `build/`, `project/`, `import/` |
| `docs/` | Current guides (`docs/guides/<area>/`), `architecture.md`, `changelog.md`, this file |

One README in the repository root. Screenshots go to `docs/images`, never the root. Per-version notes go to `docs/changelog.md` (there is no `releases` folder).

## 3. Code style

- `stylua.toml` is law: four spaces, ~100 columns, single quotes. Format first-party Lua with `stylua --syntax LuaJIT` on `source/engine source/game validation/tests main.lua conf.lua` when stylua is available. Do not reformat vendor code or historical comparison fixtures.
- Blank lines between sibling functions and logical phases. Runtime modules export named tables in this order: imports, locals, module table, helpers, functions, final export. Use explicit `create/new/build/install/register` entry points.
- Comment non-obvious invariants, units, ownership, callback boundaries and cache invalidation. Do not narrate obvious assignments or comment every function.
- Keep allocations out of hot loops; keep native callback lifetime and JIT safeguards.
- Shaders keep **CRLF** line endings where the file has them (`world.glsl`). When editing with Python, open with `newline=''`; a text-mode rewrite turns the whole file into a diff.
- Tests must be **short** and focused (a handful of checks per feature). Test descriptions are English sentences.

## 4. Modules and requires

- Relative requires: `require('./part')` same folder, `require('../x.y')` one up, `require('../../x')` two up; the rest is a dotted name (`'./solvers.twoBone'`). Use absolute `source.*` names only for modules more than two folders away.
- Relative requires belong at **file top level**. Inside functions use the absolute name (each relative call inspects the stack). Never tail-call a relative require (`return (require('./part'))`).
- Plugin manifests name modules as `./nodes.navMap`. Scene scripts are relative to the scene root; scene packages use the `scene.` prefix (`require('scene.scripts.x')`) and `scene://` for asset URLs.
- `katsa.filesystem.getDirectoryItems/getInfo/read/load` list and read files (also from archives). Scene code gets its root from `context.root`.
- Keep game features in `source/game`, engine services in `source/engine`, third-party artifacts in `vendor`. The core must **never** require a plugin.

## 5. Build, run, test

- Run the dev host from the repo root: `xvfb-run -a luajit tools/dev/katsa.lua . <flags>`. `tools/dev/runTests.sh --test-v108.6 [timeout]` wraps it and prints pass/fail counts.
- Current focused suite: `--test-v108.7` (inspector policy duplicates). Probes: `--test-v108.7.hills` (car on hills, `KATSA_QUALITY`), `--test-v108.7.resize` (live window resize) , `--test-v108.7.debug` (physics debug cost) , `--test-v108.7.profile` (profiler stages of any scene, `KATSA_SCENE`). Previous suite: `--test-v108.6` (ribbons, collision-pose, car drift/flip checks; 103 checks, ~2.5 min; keep every test under 5 minutes: draw only when a check needs a frame). Previous suite: `--test-v108.5` (front-face winding, IK, InverseKinematics3D node, uiStyler style files, ScrollFrame motion, car body sharing, hover coalescing, console rows, menu loading label, Ctrl+C, net throttle, packaging, touch zoom, auto collision, .blend import; 137 checks). `--test-v108.5.cars` is a **diagnostic probe** (not a pass/fail suite) that drives multiplayerCars on foot and in a car and prints per-stage timings.
- Regression suites worth running after UI/render changes: `--test-v106.8` (991 checks, must pass), `--test-v108.4`, `--test-v108.1` family. Known old failures unrelated to recent work: `--test-v105` ("Native contact bridge") and `--test-v50` (Screen UI check). Do not "fix" them blindly; compare with the last known-good branch first.
- Probe tooling: `validation/tests/versions/v108_4/shadowProbe.lua` renders frames to `~/.local/share/Katsa/katsa-engine/tmp/<dir>/fNN.png`:
  `KATSA_SHOT=tmp/<dir> KATSA_SCENE=<scene> KATSA_FRAMES=<n> xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.4.shadow`
  Env hooks: `KATSA_CAM="x,y,z,pitch,yaw"`, `KATSA_SHADOWVIEW`, `KATSA_NORMALVIEW`. Look at the PNGs (Read tool) for anything visual; build contact sheets when comparing frames.
- Long runs: use `timeout`, background tasks and a log file. A stray `cat` or any command waiting on stdin hangs the shell. `pkill -f` can kill your own shell if the pattern matches the command line.
- Every feature needs: a short test in the current `validation/tests/versions/vNNN/` folder wired into `focused.lua`, an entry in `registry.lua` when it adds a flag, a docs update, and a `docs/changelog.md` line under the current version.
- Shared physics/spatial infrastructure changes need regression tests for **both** dimensions, scene smoke tests, mixed-world lifecycle checks and current docs.

## 6. Git and releases

- Current line: branch `v108.7` (continues `v108.6`) (version string in `source/engine/core/version.lua`). `v108.4` is the last known-good release and must stay untouched; each release gets its own branch. Do not push to `main` without the owner's word.
- Commit and push regularly (the session Stop hook demands that uncommitted work is committed and pushed). Commit messages end with the trailers the harness gives you (`Co-Authored-By: ...`, `Claude-Session: ...`).
- Git cannot store empty directories. Record intentionally empty scene folders in `tools/project/emptyDirectories.txt` (`python tools/build/restoreEmptyDirs.py --update`) and recreate them with `python tools/build/restoreEmptyDirs.py`. Never add marker files. The engine must never require an empty folder.
- Archive: `python tools/build/packageProject.py --output dist` (omits `validation/` unless `--with-validation`).
- Update `docs/changelog.md` and dependency docs when changing structure. Follow the owner's requested version name.

## 7. Rendering and GL

- The GL state layer (`source/katsa/graphics/renderState.lua`) caches "applied" state. **A cache that claims state the driver does not have is the worst bug class here.** Example (fixed in v108.4): with culling off the front-face winding was never sent, `gl_FrontFacing` flipped intermittently and double-sided skinned meshes lost lighting. `applyCull()` now sets `glFrontFace` for every cull mode before any early return. When a rendering symptom is intermittent, suspect cached state first.
- Skinned meshes derive the normal matrix in the vertex shader from the same model matrix as positions (`world.glsl`).
- Debug views: F4 > *Shadow view* (green lit, red shadowed, blue not evaluated; brightness = cascade) and *Normal view* (normals as colour). Use them before theorising about shadows.
- Shaders are written in one dialect and translated to GLSL 330 core (desktop) / GLSL ES 300 (mobile). All engine shaders must compile on both targets.
- Quality profiles `Low/Medium/High` (`Environment:applyQualityProfile`) lower cost without removing features; `renderDensity` is the render-resolution scale; `Environment.rendering.vsync` drives vertical sync.
- Camera3D: `projectionMode` Perspective/Orthographic, `fov`, `orthoSize`, `zoom`, `orthoNear` (default `-far`). Project/pick/cull only through `camera:project/screenRay/viewToScreen/pixelsPerUnitAt`; never divide by `camera.focal` in new code; use `camera.nearClip` for the effective near plane. Ortho cameras skip software occlusion culling.
- Camera2D has immediate transforms and no smoothing; keep projection, inverse pointer conversion, zoom and FOV mathematically consistent.
- Missing/empty UI images and missing model files render cached **diagnostic assets** (checker), never fatal errors from a render callback.

## 8. Nodes, worlds, physics

- Physics by dimension: `source/engine/physics/2d` (Box2D) and `3d` (facade + Oimo/Jolt backends); nodes in `source/engine/nodes/physics/2d|3d`. New dimension-specific classes end with `2D`/`3D`. Keep public compatibility aliases.
- Never change the global `katsa.physics` meter per world; convert through each Physics2D instance. Dispatch contact events after the native solver unlocks; keep transactional collider replacement, constraint ownership and teardown order.
- Advance each simulation **exactly once**. World2D updates physics from `UI:update(realDelta, simulationDelta)` unless `autoUpdatePhysics = false`; physical example scenes disable it and step Box2D in `systems/simulation.lua:update2D`, then refresh camera follow.
- Each World2D/World3D has an independent `timeScale` (0..100). Never multiply parent and child clocks. `manager.time.scale` is a separate application override. Preserve zero-time pause semantics.
- Spatial 2D/3D use **Y up**; screen UDim2 layout is Y down; convert at the boundary (Camera2D, spatial UI, pointer inversion, image-collider rows). Downward gravity is `{0,-1}` / `{0,-1,0}`; gravity policy lives in `engine/world/gravity.lua`.
- Node2D/Node3D are spatial groups, not folders. Never sort authoritative `children` arrays for presentation; use the layout-order view.
- Collider2D is physical; visuals are UINode children. Image-derived colliders are built from alpha only when inputs change; never silently substitute a convex hull. Collider3D Points are body-local; extraction copies vertices and never aliases render geometry. GeometrySource reuses the model importer registry.
- Editor node references use the common `nodeReferences` policy; use supported editor kinds (vector/node), do not invent new field kinds.
- Each world owns one required `Environment` node (debug, particles, lighting, shadows, sky, fog). Keep 2D and 3D Workspace debug exposure symmetric.
- Per-fixed-step gameplay state that drives visuals goes through `engine/animation/stepValue.lua` and is sampled with the physics interpolation alpha. Camera2D follows the interpolated pose.
- Use `currentCamera` / `setCurrentCamera`; canonical names in examples, not historical aliases.

## 9. UI

General: UINodes are in `source/engine/ui`; layout is lazy (`ui:layout()`), changes call `ui:invalidate()`. Use the shared `TextBox` for editable strings/numbers (UTF-8 editing in `ui/widgets/textEditor.lua`, focus in `textFocus.lua`; consume focused typing before gameplay shortcuts; release focus on destroy). Visual nodes use the named `layerGroups` registry. Reuse `ui/widgets/collapsible` for example control panels.

### ScrollFrame (v108.5)
- Files: `ui/nodes/scrollFrame.lua`, `ui/layout/scrollCanvas.lua`, `scrollLength.lua`, `ui/scrolling/scrollBar.lua`, `UI:wake/updateScrolling` in `ui/init.lua`.
- Properties: `inertia` (0..1, default 0.6), `overscroll` (0..1 of the window, default 0.25; 0 = hard stop), `bounceSpeed` (default 14, visible only when overscroll > 0), `dragWithMouse` (default **false**).
- **Touch always swipes. The mouse swipes only when `dragWithMouse` is on** (pointer id `'mouse'`); wheel and scrollbar-thumb drag work regardless. Do not break this gate.
- Model: `scrollX/scrollY` stay clamped to the canvas. The finger overshoot is kept in raw excess `_exX/_exY`; displayed stretch `_overX/_overY = limit*excess/(excess+limit)` is subtracted in `getChildOffset*`. Anything that measures child positions (`scrollLength`) adds the over-offset back. A frame with motion registers via `ui:wake(node)` and is stepped from `UI:update(realDt)` until `hasMotion()` is false. `ui:scrollBy` and the wheel stop any glide.
- Release speed counts only if the last move was < 0.1 s ago.

### uiStyler plugin
- `source/plugins/uiStyler` (`styler.lua`). Selectors: `*`, `Class` (isA), `.tag`, `Class.tag`, `#Name`, and a **bare lowercase word = tag** (`uicorner`). Specificity: `*`0, class 1, tag 10, class+tag 11, name 100; later rules win ties.
- Values: plain, `'$token'` from the active theme, nested tables resolved recursively, or `function(tokens, node)`. Pseudo properties: `corner = n` (+ `cornerScale`) creates a `UICorner`, `stroke = {color, thickness, transparency}` a `UIStroke`. A property the styler set is restored to its authored value once no rule sets it.
- **Style files**: a scene keeps styles in `assets/styles/*.lua` and loads them with `styler:loadStyles(context.root .. '/assets/styles')`. A file returns a map `{ uicorner = { corner = 10, cornerScale = 0.1, backgroundColor = '$panel' } }` or a list of `{selector, values}`. One style sets many values at once. `extends = 'other'` (or a list) merges earlier styles. `styler:style(selector, values)` does the same from code; `styler:sheet(list)` replaces all rules; `setTheme` restyles every applied root.
- Docs: `docs/guides/ui/uiStyler.md`. The `launcherShowcase` scene is the reference (`assets/styles/launcher.lua`).

### Other
- `canvasSize`, scrolling axes, scrollbar insets: see `docs/guides/ui/scrolling.md`.
- Mobile controls: the joystick relocates away from scene UI; keep runner touch actions accessible; hide free-3D-camera controls when no active 3D camera exists.
- Normal runtime errors keep an interactive error screen and save `last-error.txt` (ten crash-history slots); automated test modes may exit immediately.

## 10. Animation and IK

- `Animator` (`engine/nodes/animation/animator.lua`): `evaluate pose → modifiers → model:update(0)`. `Animator:update` rewrites **all** node TRS every pose evaluation, so anything that adjusts bones must run as a modifier (`addModifier/removeModifier`, priority-sorted, called with `process(self, step)` just before the matrix rebuild). Poses are model-space relative to `model.root`; convert with `root:getWorldMatrix()` for world targets.
- Skeleton data: `model.nodes` 1-based, children 0-based indices, `translation/rotation{x,y,z,w}/scale`, row-major matrices with translation at 4,8,12.
- Flipbook/sprite animation: clips live in XML (`assets/animations/player.xml` for the runner) loaded through `engine/animation/formats/flipbookXml.lua`; never duplicate frames/fps in Lua; validate manifests once at scene creation.

### IK plugin (`source/plugins/ik`)
- Core: `quat.lua` (Hamilton quaternions, shortest-arc `fromTo`), `skeleton.lua` (bone access and local/model/world rotation, `aim`, `chain`, `limitLocal`, `snapshot/blend`), `modifier.lua` (`SkeletonModifier` base: `influence`, `priority`, `debug`, `process` with influence blending, `drawDebug`).
- Solvers (`solvers/`): `TwoBone` (law of cosines with pole, softness), `LookAt`, `Fabrik`, `Ccd` (per-joint limits), `Jacobian` (damped least squares), `Spline` (Catmull-Rom, arc-length placement), `FK` (euler Z·Y·X per bone).
- **Node**: `InverseKinematics3D` (`nodes/inverseKinematics3D.lua`, registered in the manifest `nodes`). Property `type` selects the solver; per-type properties show conditionally through `visibleWhen`; bone dropdowns are built from the target model (`Schema.options` accepts a function of the target). Target/pole use `kind='node'` references. New solver = new file in `solvers/` + a type entry + conditional properties + a test.
- Show scene `ikLab`: both hands hold a ball that moves, elbows bend toward pole hints, an arm solver switch. Keep it visually clear (verified by screenshot grids).
- Docs: `docs/guides/animation/ik.md`. Tests: `v108_5/ik.lua`, `ikNode.lua`.

### Ribbons (v108.6)
- `Beam3D` / `Trail3D` (`nodes/effects`, shared `ribbon.lua`) are drawn by `source/engine/ribbons` (`world.ribbons`) through the particle sprite shader (`ribbonPremultiply`, `ribbonEmission`, `particleDetach` uniforms). Ends are any Node3D. Trail3D has `trailMode` Single / Dual. Image config is the common component (`texture`, `imageMode`...). Shadow options come from `components/shadowing.lua` and the caster proxy from `graphics/shadows/casterProxy.lua`, shared by particles and ribbons: extend those, do not copy them. Mesh3D and the lights use the same components. Camera/layer-group visibility goes only through `components/layering.lua` (`Layering.sees`) and the render cutoff through `components/renderRange.lua`; never write `bit.band(node.layers, camera.layers)` or a `maxDistance` sphere test inline. Visual nodes take colour/transparency from `components/tint.lua` and brightness from `components/brightness.lua`; plain deep copies come from `core/tables.lua`, vector helpers from `math/math3d.lua` (`unit`, `cross`, `clamp`): do not add private copies.
- `World3D:create(class, props, parent)` ignores `props.parent` for most nodes (the Effects folder is used); pass the parent as the third argument. Ribbon nodes honour `props.parent`.
- Docs: `docs/guides/rendering/ribbons.md`. Demo: `ribbonLab`. Tests: `v108_6/ribbons.lua`.

## 11. Plugins

- Layout: `source/plugins/<name>/{plugin.lua,init.lua}`. Manifest fields: `name`, `title`, `version`, `description`, `requires`, `nodes = { Name = './nodes.module' }`, `extend` (settings/methods for existing node classes), `debug` (section in `Environment.debug`). Scenes opt in with `plugins = { 'name' }` in `settings.lua`; code uses `require('source.engine.plugins').require('name')` or `Plugins.activate(world, names)`.
- Custom node definitions (`specialNode.register`): `base`, `properties` (descriptors with `default,min,max,hint,options,visibleWhen,kind/nodeClass`), `initialize`, `update`; extra methods are copied to the class.
- Inspector schema (`engine/editor/inspectors/schema.lua`, `schemaFields.lua`): `Schema.visible/descriptor/options/hint`; `visibleWhen` accepts `{key,equals}`, `{key,oneOf}`, `{key,present}`, a function, or an array (AND). Add new inspector keys to the class `propertySchema` and to `schemaFields.lua` groups.
- `pathfinding` provides `NavMap` and a debug view (`Environment.debug.pathfinding`); `ads` is a provider-only plugin (rewarded video, API keys via config). Docs: `docs/guides/development/plugins.md`.

## 12. Scenes and the collection runtime

- Scene folder: `settings.lua`, lifecycle-only `main.lua` (system discovery/order is visible there), `assets/`, `nodes/`, `systems/`, `scripts/`. Composition lives in `scripts/content.lua`; other scripts are grouped by responsibility (builders, behaviors, lighting, animation, data, catalog); UI entry is `scripts/ui/interface.lua` or `controller.lua`. Only create categories you use.
- Register scenes in `source/game/sceneCatalog.lua` (`{ id, path }`). Example scenes run on the **common collection runtime** (Workspace, navigation, Stats, Debug, Tools); a minimal standalone Host is only for independent games. `main.create` may call `preparePresentation`.
- Pause menu: `source/game/runtime/pauseMenu.lua` (`attach(scene, true)` keeps time running, used by multiplayerCars).
- Host vs Game runtime matters: collection scenes run inside the Host; check which runtime a feature needs before assuming globals.

## 13. Multiplayer and multiplayerCars

- `katsa.net` is a separate module over the fixed-step loop; Server/Client own authority, bodies expose get/set state only. Unreliable remotes via `remote:unreliable()`; kicks via `Server:kick(player, reason)`.
- multiplayerCars (`source/game/scenes/multiplayerCars`): cars with suspension/deformation, up to 4 seats, replication, bots following a path, chat (Enter, `[HOST]` tag), player list (Tab, host-only Kick), voice chat (push-to-talk V, μ-law codec, 3D playback), host tools in the Tab panel. Key files: `scripts/content.lua` (Session, changeCar on E, HUD), `scripts/game/{carEntity,gameClient,gameServer,voice}.lua`, `scripts/view/{carView,carModel,skid,carMesh}.lua` (carModel = Duke 69 GLB parts and maps, skid = smoke and Trail3D marks, carMesh = procedural fallback). Space is the handbrake in a car; `needsReset` is only for falling. Tests drive with `actions.keys.up/right` (not `keys.w`). End-to-end test: `validation/tests/versions/v108_4/carsScene.lua`.
- **Car lag - resolved diagnosis (v108.5)**: the owner's profiler/stats exports show ~105 FPS (9.5 ms frames) while driving, including after wheels are lost; every lag window (FPS ~20, draw 30-120 ms, frame times in multiples of the vsync interval) began right after the console was opened for an export and ended when it was closed. Cause: `consolePanel` laid out 200 log lines every frame; it now lays out only the visible rows (Screen UI cost of the open console 15 -> 4 ms in the sandbox). Other findings: the spawn hitch of a new car (`{ unpack(vertex) }`, fixed), per-event `Input:hover` (coalesced per frame), per-call closures in `Batch.addQuad` / `triangle` and an args table in `G.draw` (removed, ~30% less draw garbage). Still slow by design: building a scene from the menu click (~600 ms inside `mousereleased`; the menu scene shows its own "Loading..." label first; the engine has no loading UI) and the first V press (~300 ms to open the microphone; it is not opened ahead of time on purpose, because capture is a privacy-relevant device). The in-game Host button itself takes ~60 ms. Beware `{ unpack(t) }` on large vertex lists: it is slow here. Other debug overlays (Stats panel, F4 menu, diagnostics) may have the same all-rows-every-frame pattern; check them when someone reports lag with an overlay open.
- Hitboxes vs drawn scene (v108.6): everything that is drawn from a render pose must also be *placed* at it. The seated walker capsule is teleported to the seat at the car's render pose every frame (`Walker:placeAtSeat`, offsets along the car's up axis), and the host's stand-in of another player's car follows the drawn replica (`PhysicsCar:followDrawn`). Measure with `--test-v108.6.poses`; regression `v108_6/carPoses.lua`. Open: the chassis box centre is 1.0 m above the model origin but the hull mesh centre is about 0.63 m, a static ~0.37 m offset along the car's up axis (owner decision pending).
- Shadow map in multiplayerCars is 1024 (was 2048: 400 MB atlas redrawn each frame because cars move).

## 14. Assets, XML, images

- Image-bearing nodes use `components/image.lua` (sampler, XML and UV policy). XML mode: `xml` visible only in XML mode, `atlasFrame` editable in Atlas/XML; XML owns grid/filter and fills `image` automatically but `image` stays an editable override. Rebind only when the manifest path or resource owner changes; rendering never creates playback or resets `atlasFrame`.
- Invalid XML or incompatible atlas art reports diagnostics and renders a checker; it never asserts from a render callback.
- Models: glTF accessors are read with typed arrays; preserve glTF transforms; cache successful and failed loads. Skin limits: `docs/guides/rendering/skinLimits.md`.
- Fonts: `font` property on TextLabel/Button/TextBox resolves like image paths (`shared://fonts/test-font`); a missing file warns and falls back.
- Save directory: `Katsa/katsa-engine` (older builds used a nested folder; leave old files alone).

## 15. Sandbox pitfalls

- No audio device (ALSA noise is harmless), no GPU: software GL only. Outbound network goes through an allowlist proxy; only package registries and GitHub work.
- `jit.p` output is GL-bound and uninformative for render cost; use the engine profiler (`manager.profiler`, stages: Scene update, Node/gameplay/physics update, Cars: *, Shadow build, Main submission, Screen UI ...).
- Windows-only behaviour (e.g. "No answer from the server" on multiplayer) needs the owner's confirmation; do not claim it fixed from the sandbox.

## 16. Open items (keep this list current)

- multiplayerCars backlog (owner, not started): (1) wheels spin backwards when driving forward and vice versa; (2) steering and motion must be physical through the wheels: no front wheels, no turning; (3) after many hits the dented vertices drift backwards and the hood stretches into a strip (cap the accumulated offset or keep dents relative to the rest pose); (4) adapt the collision to the deformation, as a simplified shape that follows the car geometry without fine detail.

- Debug overlays: audit the Stats panel, F4 menu and diagnostics panel for per-frame work proportional to their content (the console had it). Idle Screen UI is ~3.5 ms of a 9 ms frame in multiplayerCars (pure Lua ~2 ms in the sandbox; ~63 batch flushes per UI draw). Remaining Lua hot spots: `transform.snapshot` via `push('all')`, per-node change tracking (`changeTracking`/`valueSnapshot`), `polyline` borders, `splitLines`; measured in the sandbox, the F4 debug menu adds ~3 ms Screen UI while open and the F2 Workspace ~9 ms (+1.5 ms update). The first microphone open (~300 ms) still blocks one frame. `--test-shadows` fails on the baseline too (`validation/tests/integration/shadows.lua:11` indexes a missing `sun`); it is stale, do not trust it.
- **Actor node (owner's item 12, not started)**: parallel scripts like Roblox Actors. LuaJIT has no shared-memory threads, so the plan is one Lua state per Actor on a native worker thread (native layer), message passing (`SendMessage` / `BindToMessage` style, copied or serialized values) and a shared table in FFI memory for bulk data; scene nodes are never touched from a worker. Decide the API with the owner before building. Order: after blend-shape follow-ups, before item 11 (native rewrite).
- Offer node representations for remaining function-only plugins (owner wants plugin features visible as nodes; `ads` excepted).
- Lag at high TimeScale (5) mitigation; README screenshots; launcher UI last.
- Models: `.blend` import and `-col` / `-colonly` auto collision are implemented (`import/blend.lua`, `import/autoCollision.lua`, docs in `guides/import/models.md`); the real Blender export (`import/blendExport.py`) has not run yet - ask the owner to try a real `.blend` and report. Possible follow-ups: `-convcol`, `-trigger`, per-mesh settings.
- **Android (first device test, owner's Poco M6 Pro 4G)**: menu and 2D scenes lagged (list scrolling), multiplayerCars ran ~70 FPS, Stats open dropped to 9 FPS; the desktop probe `--test-v108.5.menu` shows only ~2 ms and 58 draw calls, so the cost is GPU fill / driver, not Lua. Mitigation shipped: 720 px render height + UI scale 540 units (see changelog); NOT yet confirmed on the device. If still slow ask for the Stats panel (it shows `JIT ON/OFF` and per-stage ms). Suspects left: LuaJIT not compiling on device, stencil/clip and overdraw of full-screen panels, Stats panel text cost.
- Build: `python tools/build/packageKatsa.py` is the single packager; fused `--test-*` flags without an explicit game path are not picked up by the registry (`katsa Game --test-v108.5` works) - investigate if it matters.

---

## Appendix A. Detailed conventions (original list, kept verbatim)

- Physics is categorized by dimension: `source/engine/physics/2d` contains Box2D integration and `source/engine/physics/3d` contains the 3D facade and sibling Oimo/Jolt backends. `physics/init.lua` is a compatibility entry point for 3D only; add new implementation code inside the appropriate dimension.
- Physics nodes are grouped under `source/engine/nodes/physics/2d` and `3d`. New dimension-specific spatial, collider, body, camera and constraint classes end with `2D` or `3D`. Preserve existing public compatibility aliases.
- World2D owns its optional Physics2D and Camera2D. Screen widgets remain camera-independent. Spatial Node2D transforms use logical world units with Y up and counterclockwise degrees; do not reuse UI layout arrays for physics positions.
- Never change the global `katsa.physics` meter per world. Convert units through each Physics2D instance. Dispatch user contact events after the native solver unlocks, and preserve transactional collider replacement, constraint ownership and teardown order.
- Advance each simulation exactly once. World2D updates its physics from UI:update(realDelta, simulationDelta) by default; pass the scaled simulation delta separately from UI wall time; set `autoUpdatePhysics = false` before stepping it explicitly from a scene system. Camera tracking and UI input must use the documented world/screen conversions.
- Changes to shared physics or spatial infrastructure require native regression tests for both dimensions, scene smoke tests, mixed-world lifecycle checks and current documentation. Keep 2D test commands available through the shared test registry.


- Write all project content in English: code, comments, documentation, test descriptions, scripts, user-facing text and filenames. Russian is reserved for conversation with the user.
- Preserve the v101 Lua style defined by `stylua.toml`: four spaces, a 100-column target and single-quoted strings. Separate sibling functions and logical phases with blank lines.
- Explain non-obvious invariants, units, ownership, callback boundaries and cache invalidation. Do not narrate obvious assignments or add comments to every function.
- Modules require siblings and nearby files relatively: `require('./part')` (same folder), `require('../x.y')` (one up), `require('../../x')` (two up); the rest is a dotted name. Use absolute `source.*` names only for modules more than two folders away. Relative requires belong at file top level (inside functions use the absolute name: each relative call inspects the stack). Never tail-call a relative require (`return (require('./part'))`). Plugin manifests name their modules as `./nodes.navMap`; scene scripts are relative to the scene root. See `docs/guides/development/scenes.md`.
- Keep game features in `source/game`, engine services in `source/engine`, and third-party artifacts in `vendor`. Keep physics adapters in sibling backend directories.
- Do not hand-format generated vendor code or historical comparison fixtures. Preserve upstream license notices and record dependency versions and local patches.
- Preserve public APIs and simulation behavior during style maintenance. Keep allocations out of hot loops and retain native callback lifetime/JIT safeguards.
- Runtime modules export named tables: imports, local bindings, module table, helpers, functions, final export. Use explicit create/new/build/install/register entry points; assemble backend methods at load time.
- Keep one project README in the repository root. Current guides belong in `docs`; per-version notes go in `docs/changelog.md` (there is no `releases` folder; results and logs live in Git history and tags). Screenshots belong in `docs/images`, never in the repository root.
- All tests, fixtures and validation reports live under `validation/` (`validation/tests`, logs in `validation/logs`, which is not committed). Game archives omit `validation/` unless packaged with `--with-validation`.
- Optional features that the core does not need (pathfinding, ad providers...) are plugins in `source/plugins/<name>/` with a `plugin.lua` manifest, loaded through `source/engine/plugins`. The core must not require a plugin.
- Third-party code, including Box2D and the stb headers used by the native layer, lives in `vendor`; `native` holds only the project's own C/C++ sources.
- Update `docs/changelog.md` and dependency documentation when changing structure. Follow the user's requested version name.
- Verify changes with the relevant katsa tests, formatting checks and native integrity checks before packaging a release.

- Scene composition belongs in scripts/content.lua. Keep other scene scripts in responsibility-based categories such as builders, behaviors, lighting, animation, data and catalog. Create internal categories only when used.
- Keep UI entry modules at scripts/ui/interface.lua or scripts/ui/controller.lua; place supporting UI modules in appropriate scripts/ui subcategories. Executable systems remain directly under systems for the scene-owned startup loop.
- Preserve empty scene categories as archive directory entries in project/scene packers and TAR conversion. Do not add marker files to retain empty folders.

- Camera2D has immediate transforms/tracking and no built-in smoothing. FOV changes its reference-plane visible area; screen UI stays independent. Keep projection, inverse pointer conversion, zoom and FOV mathematically consistent.
- Image-derived Collider2D geometry is built from alpha only when inputs change. Preserve transparent holes for Detailed quality, retain explicit resolution/fixture budgets, and never substitute a convex hull silently for a requested concave manual polygon.
- Collider3D Points use body-local editable coordinates with optional triangle indices. Mesh extraction must copy source vertices/topology and must not alias or mutate render geometry. Keep automatic geometry sources separate from baked editable points.

- Keep example scenes on the common collection runtime so Workspace, navigation, Stats, Debug and Tools remain available. Minimal standalone Host is for independent games or explicitly minimal examples. Scene main.create may conditionally call preparePresentation for portable collection presentation.
- Each World2D and World3D has an independent timeScale (0..100). Pass the common application delta to 2D before applying any enclosing World3D scale. World2D.updatePhysics applies its own scale; never multiply by both parent and child clocks. manager.time.scale is a separate application override.
- Processed spatial/UI scripts use their nearest World2D clock, while other nodes use their World3D clock. Preserve zero-time pause semantics and refresh a processed node's clock owner after reparenting. A nested viewport World3D does not inherit its enclosing World2D timeScale.
- Editor node references must use the common nodeReferences policy so dimension and world ownership checks match the picker and writer. Use supported editor kinds such as vector/node; do not invent vector2/color field kinds that the shared editor cannot render.

- Node2D and Node3D are spatial groups, not organizational folders: retain Position, Rotation and Scale. Node2D uses Vector2 scale and full affine child transforms. Bake affine transforms into Box2D fixtures transactionally; do not rebuild geometry for rigid motion or native float round-trip noise.
- Keep Collider2D physical, with visual UINode children (or visual siblings under Body2D). Relative UDim2 fills the spatial parent's local size. HUD stays camera-independent; spatial visuals and pointer inversion must share camera, scale, shear and interpolation transforms.
- Never sort authoritative children arrays for UI presentation. Use the layout order view for drawing and picking; Workspace and hierarchy APIs retain insertion order.
- World3D defines fixed world coordinates; omit transform fields from its inspector. World2D transparency composites its whole visual plane without pausing physics. Cache spatial UI rasterization independently of body movement and release owned canvases when nodes are destroyed.
- World gravity is scalar magnitude plus dimension-correct GravityDirection. Preserve legacy solver vector options, normalize direction for simulation, observe each world's edits and wake dynamic bodies only on gravity changes. Keep the shared gravity policy in engine/world/gravity.lua.

- Spatial 2D and 3D both use positive Y up. Keep screen UDim2 layout Y down; Camera2D, spatial UI surfaces, inverse pointer coordinates and image-collider alpha rows perform that conversion at the boundary. Downward GravityDirection is {0,-1} / {0,-1,0}.
- All physical example scenes explicitly disable UI autoUpdatePhysics and step Box2D in their own systems/simulation.lua:update2D. Refresh camera follow after stepping. Preserve independent World2D timeScale and leave menus responsive when simulation is disabled.
- Visual UINodes, visual modifiers/gradients and SurfaceAppearance3D use the common named layerGroups registry. Filter rendering, picking and modifier layout consistently, and invalidate material/UI caches when viewer groups or the matrix change. Camera2D is the spatial viewer; World2D is the HUD viewer.
- Reuse ui/widgets/collapsible for example control panels. Keep runner touch actions accessible and hide free-3D-camera controls in worlds without an active 3D camera. Example animations and controller logic stay inside their scene; reusable atlas playback belongs in engine/animation/flipbook.lua.
- Orientation indicators are debug overlays, disabled by default. Project camera-relative axes after world/UI rendering; do not modify scene transforms to draw them.

- The 2D runner authors atlas metadata and animation clips only in assets/animations/player.xml. Load them through engine/animation/formats/flipbookXml.lua; keep state selection in the scene's Lua controller. Do not duplicate clip frames, fps or atlas dimensions in Lua. Validate XML manifests once at scene creation, never per frame.

- XML image mode uses the shared image component and flipbookXml binding cache. Keep xml visible only in XML mode and atlasFrame editable in both Atlas/XML modes. XML owns atlas grid/filter and automatically fills image from its image attribute; keep image (or material colorMap) editable as an optional override. Empty image fields must preserve the last resolved XML sprite when switching modes; rendering must never create playback, restart clips or reset atlasFrame. Rebind only when the manifest path or resource owner changes. The manifest is metadata; retain separate PNG assets and scene-owned state selection.

- Missing/empty UI image sources and missing model files use cached diagnostic assets instead of fatal errors. Preserve explicit text-only buttons and intentionally untextured materials. XML must not validate placeholder image dimensions against real sprite dimensions or crop the diagnostic checker to one atlas cell. Keep manual XML image overrides when replacing manifests; update automatically filled paths only.

- Use the shared TextBox node for editable strings and numbers, including inspector popup fields. Keep UTF-8 editing/selection/history in ui/widgets/textEditor.lua and keyboard ownership in textFocus.lua. Consume focused typing before gameplay shortcuts and release focus on destruction. Preserve Apply/Cancel semantics in Workspace.
- Normal runtime errors must retain an interactive error screen and save last-error.txt; do not exit on Escape or queued gameplay events. Automated test/smoke modes may exit immediately. Keep the error screen independent of scene/UI state so a failing renderer cannot hide its own report.

- Particle dimensions share system/simulation/lifetime/emitter defaults and image policy; put spatial rendering/sampling/visibility in particles/2d and particles/3d. Keep existing 3D entry points as compatibility wrappers. World2D:updatePhysics advances 2D particles exactly once with that world's clock, even without a physics solver. Keep point sweeps budgeted and pooled.
- All image-bearing nodes use components/image.lua for sampler, XML and UV policy. Particle clip selection belongs in particles/image.lua. Missing/invalid XML or incompatible atlas art must report diagnostics and render a checker, never assert from a render callback. Preserve legacy decal.mode and particle atlas controls.
- Each World2D/World3D automatically owns one required Environment node. In Workspace, group Debug, Particles2D/Particles3D and dimension-specific render/lighting categories beneath Environment. Keep settings tables shared with runtime services and available before service creation. Keep F4 controls grouped by dimension/responsibility. Crash history retains ten fixed slots and a legacy last-error.txt copy; preserve automated failure exits.

- Keep 2D and 3D Workspace debug exposure consistent. Do not add a separate Physics2D Solver Settings row or expose solver internals asymmetrically; solver configuration belongs in scene settings/runtime APIs. F4 pause/step commands exist for both dimensions.

- Use currentCamera and setCurrentCamera for both world dimensions; Camera2D and Camera3D expose fov. Example scenes must use canonical names, not historical compatibility aliases.

- Collider3D GeometrySource accepts same-world Node3D references or model paths. Reuse the model importer format registry, scene resource scope and modelSource adapter; never instantiate visible nodes for collision-only assets. Cache successful and failed file loads. Preserve glTF transforms, apply Collider3D offsets once, and retain the last valid descriptor after invalid edits. Mesh/Model point extraction must return independent coordinates and topology.

- Camera3D has `projectionMode` (`Perspective` or `Orthographic`), `fov` and `orthoSize`; `fov` and legacy `focalLength` are one lens and the latest edit wins. Project, pick and cull through `camera:project`, `camera:screenRay`, `camera:viewToScreen` and `camera:pixelsPerUnitAt`; never divide by `camera.focal` in new code. Orthographic cameras skip software occlusion culling and zoom through `zoom` (visible half-height `orthoSize / zoom`, never by moving the camera), and clip from `orthoNear` (default `-far`) instead of `near`; use `camera.nearClip` when you need the effective near plane.
- Gameplay state authored once per fixed step that drives visuals (facing, blend weights) must go through `engine/animation/stepValue.lua` and be sampled with the physics interpolation alpha. Camera2D follows the interpolated pose of its target, never the raw solver pose.
- Git cannot store empty directories. Record intentionally empty scene categories in `tools/project/emptyDirectories.txt` (`python tools/build/restoreEmptyDirs.py --update`) and recreate them after cloning with `python tools/build/restoreEmptyDirs.py`; `packageProject.py` does this automatically. Never add marker files.

- **Net: unreliable packets and ENet's throttle (v108.5)**: ENet silently drops unreliable packets while a peer's throttle is low and reports 0% loss. `katsa_net.c` disables the throttle on connect; the engine falls back to reliable state packets when the loaded native library predates that (`katsa.net.unthrottled()`). After changing `native/src/katsa_net.c` the owner must rebuild the library for their platform. The `Net` console lines (`Server sent...`, `Client received...`, `Snapshot gap`, `held still`) are the quickest way to see delivery problems.
- **Jerky cars after Host - resolved and confirmed by the owner (v108.5)**: snapshots were sent at 20 Hz but the client received 2-7 per second for ~5 s after Host (ENet throttle, 0% reported loss); fixed in `katsa_net.c` (rebuild `katsa_net` for the platform) with a reliable-channel fallback for old libraries. Also fixed: RenderPose was applied on top of an already interpolated network replica on the host, and per-frame garbage in `Shader:send` / `G.push('all')` (~60 MB/s -> half). Open: other garbage sources (UI text/modifiers, `Batch.prepareDraw`, shadow depth pass), Android APK template: written (`android/`), needs a first real build with NDK/SDK by the owner.
