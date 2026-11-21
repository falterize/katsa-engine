# TODO — open work on Katsa

The one list of what is still open. It is not part of `AGENTS.md`: that file holds rules and how things
work, this one holds what is left to do. Keep it current: add an item when something is found, delete
it when it is done (the details of finished work go to `docs/changelog.md` and the guides).

Rules that still apply to everything here: do not cut features, verify with a probe before shipping a
fix, say plainly what only real hardware can confirm, and the launcher UI is the last stage.

## Waiting for the owner's hardware

- **SSAO banding**: see the long item below ("SSAO banding still visible").
- **multiplayerCars** wheels, steering, dents and collision: see the backlog item below.
- **Android** (Poco M6 Pro 4G): the 720 px render height and UI scale 540 mitigation is not confirmed on the device. If it is still slow, ask for the Stats panel (`JIT ON/OFF`, per-stage ms).
- **Windows-only behaviour** that the sandbox cannot show: the `katsa_threads.dll` build and the host exporting `lua*` (Actor), DWM transparency and window z-order, the freeze when leaving windowsLab, `No answer from the server` on multiplayer.
- **Real-GPU look** of what the sandbox only verifies by pixels: prefab `World2D` inside copies and inside a `ViewportFrame`, the nickname billboards of the avatar prefab.

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
