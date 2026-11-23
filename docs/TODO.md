# TODO — open work on Katsa

The one list of what is still open. It is not part of `AGENTS.md`: that file holds rules and how things
work, this one holds what is left to do. Keep it current: add an item when something is found, delete
it when it is done (the details of finished work go to `docs/changelog.md` and the guides).

Rules that still apply to everything here: do not cut features, verify with a probe before shipping a
fix, say plainly what only real hardware can confirm, and the launcher UI is the last stage.

## Waiting for the owner's hardware

- **SSAO banding**: see the long item below ("SSAO banding still visible").
- **multiplayerCars** wheels, steering, dents and collision: see the backlog item below.
- **Android touch crash (v109)**: root cause was the SDL event watch running Lua on the UI thread; fixed. If the Poco is stable, re-enable the JIT on Android (`Runtime.initialize`) and watch for impossible errors; never run Lua from SDL callbacks on other threads.
- **Android pointer tagging (v109)**: Android 11+ with targetSdk 34 tags heap pointers; LuaJIT GC64 breaks on them. The manifest opts out; confirm on the Poco that the impossible errors (`33`, compare number with string) are gone, then retry the JIT.
- **Android JIT (v109)**: on the Poco M6 Pro 4G (arm64) the log shows impossible Lua errors (`attempt to compare number with string` in `font.lua` `getWrap` on plain numbers, `bad argument #2` in the SDL poll loop): a LuaJIT trace fault. v109 runs the interpreter on Android (`jit.off()` in `Runtime.initialize`, `KATSA_JIT=1` re-enables). Confirm the errors are gone, then find the real cause (LuaJIT build flags/NDK, `v2.1` snapshot, a specific trace) and turn the JIT back on; the interpreter is several times slower.
- **Android** (Poco M6 Pro 4G): the 720 px render height and UI scale 540 mitigation is not confirmed on the device. If it is still slow, ask for the Stats panel (`JIT ON/OFF`, per-stage ms).
- **Windows-only behaviour** that the sandbox cannot show: the `katsa_threads.dll` build and the host exporting `lua*` (Actor), DWM transparency and window z-order, the freeze when leaving windowsLab, `No answer from the server` on multiplayer.
- **Real-GPU look** of what the sandbox only verifies by pixels: prefab `World2D` inside copies and inside a `ViewportFrame`, the nickname billboards of the avatar prefab.

## Platforms (goal: every device that can run it)

Status as of v109. "CI" = built by GitHub Actions; "owner" = needs a person with the device.

| Platform | Status | What is missing |
| --- | --- | --- |
| Linux x86_64 | **Done**: built and all regression suites run in CI (Mesa software GL) | Real-GPU confirmation |
| Windows x86_64 | **Done**: cross-built in CI (llvm-mingw), the owner runs the `.exe` | The `katsa_threads.dll` and DWM items under "Waiting for the owner's hardware"; no automated run on Windows |
| macOS universal (x86_64 + arm64) | **Builds in CI**; unit tests there are non-blocking until a run is confirmed | Run on a real Mac, `.app` bundle and signing |
| Android arm64-v8a, x86_64 | **In progress**: APK built in CI (engine + examples, `android/prepare.py --project`); on a Poco M6 Pro 4G the app crashes on the first touch (breadcrumbs and the crash-report screen are in to find where) | Fix the touch crash, the black screen / "not responding" at start, performance; confirm the 720 px render height |
| Android armeabi-v7a (32-bit ARM) | Build script supports it, not in the default APK | Add to the CI APK, test on a 32-bit device |
| Windows x86 (32-bit) | Not started | i686 mingw target in `tools/native/build.py`, LuaJIT 32-bit, SDL2/OpenAL 32-bit DLLs, a CI job |
| Windows ARM64 | Not started | aarch64 mingw target, ARM64 LuaJIT (JIT works there), CI job |
| Linux arm64 / armv7 (Raspberry Pi, handhelds) | Not started | aarch64 and armhf targets (cross compiler or native ARM runner), Mesa GLES/GL check, a CI job |
| Linux x86 (32-bit) | Not started | Low priority; `-m32` build |
| iOS arm64 (iOS 12+) | Not started | SDL2 + Xcode project, LuaJIT in interpreter mode (JIT is forbidden), OpenGL ES 3.0, system OpenAL, signing; CI on macOS; needs an iPhone |
| iOS 10.3.3 / iPhone 5c (jailbreak, armv7, GLES 2.0 only) | Not started, blocked by rendering | The GLES 2.0 renderer below; 1 GB RAM, so a lean profile; cross build (Theos or Xcode 13) |
| Web (browser) | Not started, needs a decision | LuaJIT does not run in WebAssembly; would need PUC Lua or Fengari and a WebGL 2 backend |
| FreeBSD and other desktop Unix | Not started | Depends on SDL2 and LuaJIT availability; low priority |

Cross-cutting work that unlocks several rows:

- **GLES 2.0 renderer** (old Android, iPhone 5c, some embedded boards): a second shader dialect and a
  reduced feature set (no instancing, UBO, 3D textures, multiple render targets). It must not remove
  features from the ES 3.0 / desktop path: it is an additional quality profile with its own tests.
- **One CI matrix**: `native.yml` builds one target per job today; make the target list data (one table
  of target, runner, toolchain, artifact) so a new platform is one line, and run the regression suites on
  every target the runner can execute.
- **Per-target smoke test**: start the dev host, render ten frames, run the unit tests (already done on
  Linux and macOS) so a platform is "done" only when it runs, not when it links.
- **Performance budget for slow CPUs** (interpreter-only LuaJIT on iOS, 32-bit ARM): the quality
  profiles and `renderDensity` are the tools; measure with the Stats panel on each device class.
- Document the supported platform list and how to build for each in `docs/guides/katsa/building.md`
  once a row turns Done.

## Engine work

- **Owner's list (2026-11-14)**: (1) SSAO (v108.8 shipped the depth-aware upsample and the soft intensity curve; the owner still has to confirm the banding on hardware) still bands over the whole screen on the owner's hardware (replicationLab screenshot: horizontal stripes on the map floor; I enabled SSAO in that scene's `level.lua` in v108.8, so it shows there; see also the older SSAO item below). (2) Audit all node classes for empty properties that do nothing, e.g. `visible` on `StorageFolder` (it is always hidden): remove them through the class `omit` list, with a test per class.
- Audit every node class for properties that do nothing (see the item above); `v108_8/noOpProperties.lua` exists, check what it already covers.
- ImGui follow-ups: Windows and Android binaries (the owner builds them or CI does), `ImGuiLayer` docking option. Debug, Profiler and Console are ImGui windows now; Explorer, Properties and the main toolbar are ImGui too (owner asked later); the audio mixer overlay and the pause menu are still the engine UI; the old Debug overlay/console/diagnostics remain as the fallback without the native library.
- **Per-layer 3D for Shader2D (done as `viewLayers`)**: follow-ups: a layer pass redraws every frame (it does not reuse frames like the main render), an inspector multi-select for the group list (it is a comma separated string), and a quality profile entry for the pass density.
- **Shadow zig-zag on skinned low-poly meshes** (owner, stareShooter Destare ear/body: dark wedges following triangle edges): suspect the facet normal from `dFdx/dFdy(worldPosition)` in `world.glsl` (v108.7 hills fix), which mixes triangles at their edges in a 2x2 quad. Not reproduced in the sandbox (Blender is missing, the orbit camera ignores `KATSA_CAM`). Prove with a probe before changing it; the fix must keep the hills acne fix.
- **SSAO banding still visible on the owner's hardware (open, v108.7 attempt did not fix it)**: stareShooter, Camera3D `position = (-4.3898, 1.2821, 0.84169)`, `rotation = (5, 220.75, 0)`: horizontal striped hatching on the checker floor with SSAO on, clean with it off. v108.7 changed `post/ssao.glsl` (slope tolerance ignores depth edges and floors at the 24-bit depth step, factor 2.0): on llvmpipe it removed the bands (also the black ground of the `shadows` scene at a low camera) but the owner's screenshot (real GPU, probably other render density / driver) still shows them, so the sandbox does not reproduce the real cause. Next: ask for `Environment.render` density and quality, render the raw occlusion target and the blurred one separately (add a debug view like F4 Shadow view), suspect depth precision of the real driver (`depth24` sampled as `r`; try `depth32f`), half-resolution depth lookup (sample the depth texture at the matching full-resolution texel) and the blur step.
- multiplayerCars backlog (items 1-3 implemented in v108.7, awaiting the owner's hardware check; the rest not started): (1) wheels spin backwards when driving forward and vice versa; (2) steering and motion must be physical through the wheels: no front wheels, no turning; (3) after many hits the dented vertices drift backwards and the hood stretches into a strip (cap the accumulated offset or keep dents relative to the rest pose); (4) adapt the collision to the deformation, as a simplified shape that follows the car geometry without fine detail.
- **AnimationTree**: a Godot-style graph canvas does not exist.
- **Models**: possible follow-ups `-convcol`, `-trigger`, per-mesh import settings.
- **Packager**: fused `--test-*` flags without an explicit game path are not picked up by the registry (`katsa Game --test-v108.5` works); investigate if it matters.
- **Prefabs**: `scene://` assigned to an existing node later is resolved against the scene that holds the world (the node cannot tell which scene wrote it); use `<name>://` or `scene.resources:canonical`. A real fix means resolving at load time in every resource loader. Not planned.

## Larger designs

Longer write-ups of open work (moved here from the former root `TODO.md`).

### UI: event-driven layout invalidation

`UI:layout()` decides whether anything changed by scanning every property of every node
(`source/engine/ui/layout/changeTracking.lua`, compiled schemas in `core/valueSnapshot.lua`).
That costs roughly 0.75 ms per call at 640 UI nodes (it was 1.2 ms before type tests stopped
going through `node:isA`), and it runs on every call of `getAbsolutePosition()`,
`getAbsoluteSize()`, `UI:hit()`, `UI:pointer()` and once per draw. The cost grows with the node
count, so large UIs (the level editor) pay for it several times per frame.

Status (v108.9): the absolute getters scan once per frame (`UI:layoutOnce`) and the scan is sparse
(0.36 ms at 611 nodes). The event-driven redesign below is only worth doing if profiles on real
hardware still show `UI:changed()`.

Goal: make `layout()` nearly free when nothing changed.

- Mark a node dirty when a layout-relevant property is written: through `__newindex` for absent
  keys, `PropertyChanges.set` for observed fields, and the managed vector `revision` for
  `position[1] = x` style writes.
- The hard part: properties stored as raw fields on the instance never reach `__newindex`, so
  they must move behind the typed/observed store (or be written through setters) before polling
  can be dropped. Engine code that writes scroll offsets, text measurements and layout results
  with `rawset` needs the same audit.
- Findings (v108.9 probe, 611 editor nodes, `ui:changed()` 1.08 ms on llvmpipe): UI vectors already
  bump the node's `_propertyRevision` (managed values, `valueTypes.assign`), but scalar properties
  (`text`, `fontSize`, `visible`, `backgroundTransparency`...) are raw instance fields: a write to
  an existing key never reaches `__newindex`, so nothing bumps. The Node3D route (move them into
  `_observedValues`, see `nodes/core/propertyChanges.lua`) makes every read of such a property a
  metamethod call, which hits drawing and hit-testing hard on UI nodes. Before any rewrite,
  benchmark the read overhead; the cheaper experiment is to gate only the `Snapshot.fields` call
  on a revision once the layout-relevant scalars are observed. Full Godot-style deferred layout
  (queue at end of frame, minimum-size propagation, container sort queue) also touches
  `layout/arrangement.lua` and `scrollCanvas.lua` and is not needed for the speed-up.
- Keep the polling scan as a debug check (`KATSA_VERIFY_LAYOUT`): run both and assert that the
  dirty flags never miss a change. The v106.8 suite (991+ UI checks) and the scene smoke tests
  are the regression net; real-GPU and Windows behaviour need the owner's confirmation.
- Until then, per-frame polling code should lay out once per frame (the level editor's
  `Kit.rect`) instead of calling the absolute getters in loops.

### multiplayerCars: collisions with other cars

- **Fixed (v108.9):** a car rammed by a client-driven car was launched (28 m/s in the probe, "into the
  sky" at time scale 4). The server keeps a kinematic stand-in for every client-driven car; its
  velocity was derived from the pose change per physics step, which is zero between network updates
  and several times the real speed on the step a pose lands, and a kinematic body never loses
  speed in a hit (infinite mass) while the real car was stopped by the same hit on its client. The
  stand-in now takes the replicated speed, and `PhysicsCar:limitPush` limits what a struck car can
  gain to the equal-mass collision result and caps hit speed and lift. Probe:
  `--test-v108.9.cars.accel` (`KATSA_SCALE=4` runs it at time scale 4).
- **Open:** the two-sided hit is still approximate. Properly, the server should run one shared
  contact with finite masses (the driver's client sends the impact, the server applies the
  impulse to the bot, and the client applies the reaction), instead of two independent solves.
- **Open, needs a decision:** car acceleration feels too fast. It matches the configuration
  (`acceleration = 24` m/s^2, 0 to 100 km/h in about 1.3 s; it was 14 before the "snappier car
  physics" commit) and both worlds step exactly once per 1/60 s, so it is tuning, not a
  server/client split artefact. Candidate: 14 to 16, with a gentler start and the top-speed taper.

## Ideas (not started, not asked for)

- Pick a single `*.katsa` automatically when the launcher finds only one.
- `tools/project/newGame.py` to scaffold a game.
- CI: run `tools/dev/testChanged.lua --since <base> --run` on pull requests instead of the full suites.
- Input action map follow-ups.
- **LOD follow-ups** (LODGroup with names, quality bias, zoom compensation, cross-fade, animation rates, shadow level and billboard level is done): automatic mesh simplification at import (pure Lua, static meshes first, cached next to the model; skinned meshes and shape keys later); choosing the level for several cameras (split screen); switching physics by distance; a dithered fade (screen-door) instead of the transparency fade; shadows from a coarser mesh instead of no shadow; billboards from several angles (impostors).
- **Temporal effects follow-ups** (history and velocity hints for `Shader2D` are done): velocity for user-shader vertex displacement, blend shapes, particles and transparent meshes, a built-in TAA pass on top of both. Check on real hardware: `rgba16f` canvases on mobile and the look of the Datamosh.
- README screenshots.
- Lag at high TimeScale (5): inherent (five fixed steps per frame); only mitigation ideas remain.

## Last

- Launcher UI (the owner decides when).
