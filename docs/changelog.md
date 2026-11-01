# Changelog

Per-version notes. Test results and logs for each release live in Git history and tags.

## v108.3

- `katsa.log` (levels log/warn/error, bounded history, listeners, `logs/latest.log`, print capture), JSON/CSV console export, crash reports as `crashes/crash-NN.log` with recent console lines. See [console and logs](guides/development/console.md).
- Workspace inspector: `Image.describe` mutated the parent class schema, so every `Frame`/`TextLabel` listed image fields (and the reverse looked like ImageLabel showing the wrong parameters). Each class now owns its schema, and writing a property the class does not declare is rejected (`Schema.hasProperty`). Focused suite: `--test-v108.3`.
The engine runs on its own katsa runtime.

- Graphics (OpenGL 3.3 / GLES 3.0 through SDL2), audio (OpenAL, silent fallback), physics (Box2D 2.3.1 in
  `katsa_box2d`), image, sound, filesystem, data and the archive readers are implemented in `source/katsa`,
  split by category (one concern per file).
- Archives: ZIP/`.katsa`, TAR, TAR.GZ and 7z (stored, LZMA, LZMA2; pure Lua decoder).
- `tools/build/packageProject.py` produces a `.katsa` archive or, with `--host`, a fused executable.
- The project is fully on the katsa API (`katsa.*`).
- Engine fixes found during the port: runtime objects are opaque values (not copied as tables),
  `graphics.push('all')` keeps the current font, shader uniforms accept plain numbers and flush queued draws,
  `SoundData:getSampleCount` counts frames, physics stays out of the JIT while native code can call back.

## v108.2

Standalone runtime foundation (Stage 2, item 6): C host, SDL2 platform, `katsa.*` core modules
(filesystem, timer, data, math, event, window, keyboard, mouse, system), `.katsa` archives,
fused executables, generic `katsa` runtime. Graphics, audio and physics ports follow in v108.3+.
See `docs/guides/katsa/building.md`.

## v108.1

Stage 2 of the migration plan, first increment. The shader translator and audio modules land here.



* **katsa layer foundation** (`source/katsa`): shader-dialect to GLSL 330 core / GLSL ES 300 shader translator, headless
  EGL platform (desktop GL 3.3 core and GLES 3.0), GL compile/link validation. Window, input, audio and 2D drawing on
  GL follow in later versions. See `docs/guides/katsa/platform.md`.
* **Audio modules**: `SoundManager` (`scene.audio.manager`), `AudioListener`, `AudioSource`.
  See `docs/guides/audio/audioModules.md`.
* **Constraint modules**: one module per constraint family under `nodes/physics/3d/constraintTypes/`; new
  `SliderConstraint3D` (`PrismaticConstraint3D` stays as an identical class).
* **Shader scopes**: `Shader2D` processes interface pixels only unless `affects3D = true`; `Shader3D` is limited to
  World3D hierarchies. Stare Shooter's retro filter and the platformer speed blur set `affects3D = true`.
* **No empty folders required**: scene category folders are no longer validated, so a repository clone or GitHub ZIP runs.

**Behaviour change.**

Shader2D no longer processes the 3D render behind it by default. Scenes that relied on that must set `affects3D = true`.

## v108

Stage 1 of the migration plan: frame-synchronization fixes and Camera3D projection modes. The `katsa` platform layer starts in the next stage.

- Fixed slow-motion stutter in per-tick gameplay state. Facing and animation blend weights authored in the fixed step (Stare Shooter body turn, walk/crouch blending) are now sampled with the same interpolation alpha as bodies through the new `engine/animation/stepValue.lua`. At TimeScale 0.1 the visual yaw changes on 110 of 119 frames instead of 12.
- Fixed Camera2D lagging behind interpolated Body2D visuals. `followTarget` now follows the drawn (interpolated) pose, which removes the jitter of the Ability Runner 2D sprite inside its Body2D at high refresh rates and in slow motion.
- Camera3D gained `projectionMode` (`Perspective` / `Orthographic`), `fov` and `orthoSize`; `near` and `far` are inspector fields. `fov` and the legacy `focalLength` are one lens (latest edit wins), so existing scenes render identically. Projection, pointer rays, picking, frustum culling, shadow receivers, billboards, world-space UI and debug gizmos support both modes. Software occlusion culling is skipped for orthographic cameras.
- Fixed skeleton animation looking like low FPS under TimeScale. `Animator.poseRate` was gated on scaled time, so a world at 0.5 posed every 2nd frame and at 0.1 every 10th. It now budgets poses per wall-clock second (`world.frameRealDelta`).
- Orthographic `Camera3D` zoom: new `zoom` property and `camera:zoomBy(steps)` (visible half-height `orthoSize / zoom`). Workspace shows `zoom`, `orthoSize` and `orthoNear` only in Orthographic mode; the mouse wheel zooms the free camera, which now inherits the scene camera's projection.
- Fixed orthographic cameras slicing the map when they approach the ground: clipping now starts behind the camera (`orthoNear`, default `-far`) instead of at a positive `near`.
- Test maintenance: the historical missing-manifest check now consumes its expected journal report, so the full legacy suite passes (1348 checks, previously one order-dependent failure).
- New guides: [Camera3D projection](guides/rendering/camera3D.md) and [smoothing per-tick state](guides/animation/stepValue.md). Updated Physics2D, testing and conventions documents.
