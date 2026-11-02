# Changelog

Per-version notes. Test results and logs for each release live in Git history and tags.

## v108.4

- multiplayerCars: hilly terrain (static Jolt bodies), chase camera orbit by dragging, no UP/DOWN buttons (`cameraButtons = false` scene setting), HUD moved below the Debug button, replicated bot route with a Path debug toggle, nitro exhaust flames.
- multiplayerCars: cars are now rigid `Body3D` bodies (Jolt) with raycast spring suspension, drive/brake/grip forces, real collisions with terrain, walls and other cars, dents from physics impacts, and self-righting respawn. The server owns the physics; clients interpolate the replicated pose.
- multiplayerCars: car authority follows the driver. A joined driver's client simulates its own car (kinematic stand-ins for the others) and the server follows its state; with no driver, or for the hosting player, the server simulates. Collisions felt by a driving client are reported to the server for dents.
- multiplayerCars: players now start on foot beside their own parked car. The on-foot character is the StareShooter controller (capsule body, crouch, walk/crouch blends, animations) driven by the shared `engine/core/stateMachine.lua`, with extra `drive` and `passenger` states. E enters the nearest car (driver seat first) or leaves the current one; touch gets Enter/Exit and Jump buttons. Walkers are client-authoritative replicated entities.
- `engine/core/stateMachine.lua`: the finite state machine from StareShooter, now shared.
- multiplayerCars: the StareShooter orbit camera replaces the chase camera for both the walker and the car (drag to orbit, wheel to zoom, wall-aware raycast, the car view eases behind the car while driving), and the scene now uses the StareShooter sky, directional sun with cascaded shadows and haze. Cars gained a steering cap by lateral acceleration and an anti-roll/pitch stabiliser so hard turns no longer flip them.
- BillboardUI inside a `ViewportFrame` showed uninitialised GPU memory ("a heap of pixels"): its canvas refresh ran inside the frame's clipped draw and inherited the scissor and stencil test. The refresh now resets them. The internal settings `Environment` of world-space UI is hidden from the explorer.
- flyingAudio: the kinematic cube is driven per fixed physics step along the exact path and rendered with physics interpolation, which removes the jerky motion.
- Graphics: `push('all')`/`pop()` and the state setters (blend, colour mask, scissor, stencil, depth, cull, winding, wireframe) no longer flush the batch or call GL when the state is unchanged; the stack snapshot no longer copies tables.
- Hosting: an unfocused or minimised window no longer freezes a hosted game. Scenes can define `updateInBackground(dt, realDt)`; the scene manager calls it instead of `update` while the window has no focus, so joining players still get answers when several apps share one PC. multiplayerCars runs its network and physics there.
- Scene `settings.lua.runInBackground` and a debug menu toggle ("Keep running when the window is unfocused") keep the full scene update running without window focus.
- Loading: model sidecars and extracted native libraries are validated with `engine/core/fingerprint.lua` (an exact full-pass fingerprint, 10 ms for 8 MB) instead of the pure-Lua SHA-256, which took most of the load time of model scenes.
- Physics: static `Mesh` colliders (triangle meshes) for terrain, with a focused test.
- Audio: OpenAL EFX is implemented (reverb, echo, chorus, distortion auxiliary sends and low/high/band-pass filters). Previously only pitch worked.
- Debug menu toggles show their real state on open; crash screen renders tabs correctly; the console (F1 or Debug > Console) is available in the game runtime and receives journal warnings.
- Shader layers now work like layer groups: `Default2D`/`Default3D` start layers, a symmetric interaction matrix (add, rename, delete, priority) replaces Suppress, and `Shader2D.affects3D` is gone (a Shader2D processes 3D when its layer interacts with `Default3D`).
- Performance: fixed a Lua heap leak in UI change tracking (a per-frame table literal grew the compiled snapshot cache, ~0.085 MB/frame in physics2D); shadow atlas sized by demand; redundant framebuffer rebinds skipped; editor panels draw without offscreen groups; GC tuned at boot.
- Fixed objects vanishing while the camera moves (depth prepass wrote into a depth-only target that fell back to the screen).
- Fixed flyingAudio crash (non-finite velocity on the first frame).
- LAN server list shows one entry per server; connection timeouts now report address, port and connection state.
- Fixed shadows everywhere: `setCanvas({ depthstencil = canvas })` without a color canvas was treated as "no canvas", so the shadow pass drew into the screen and the atlas stayed empty (the whole receiving area was shadowed). Depth-only targets are now supported, `clear(false, false, depth)` parses `false` as "skip color", and clearing honours the scissor box (needed for atlas tiles).
- Fixed the hard seam across big floors with normal maps: the tangent-frame degeneracy threshold in `world.glsl` was absolute and switched the normal map off along a line of constant depth.
- `Node:clone(properties, parent)`: deep copy of a node and its descendants (like Roblox `Instance:Clone()`). `properties` overrides fields, e.g. `vehicle:clone({ Name = 'ClonedTest' })`; `parent` defaults to the source's parent. Names registered per world (meshes) must stay unique, so a copy of `Wheel` becomes `Wheel_2`. Built from the Workspace property schema, so runtime caches and native handles are never copied.
- Fixed particle self-shadow flicker for emitters that both cast and receive shadows (the lookup is offset toward the light by the particle size). Windows source runs need the compiled libraries in `lib/` (see [building](guides/katsa/building.md)).
- Profiler named tasks: `katsa.profiler.start(name)` / `stop(name)` (cross-frame, nestable, shown while running).
- Workspace: restyled (rounded panels, accent header), tree rows with class color chips, unlimited indentation and X/Y scrolling; fixed the missing minus glyph in property category headers.
- Profiler: per-frame history, percentiles/1% low/spikes, `scope()`, session recording with JSON/CSV export (`logs/profile-*`), `--profile`, new panel with frame bars and stage shares. See [profiling](guides/performance/profiling.md).
- `multiplayerCars` scene: LAN server list, authoritative cars (suspension, nitro, four riders, dents), pathfinding bot and nitro refill by rewarded ad. `server:setAuthority`, `Net.browse().refresh(address)`, `katsa.launchArguments`.
- `ads` plugin: rewarded ads with `mock`, `admob` and `unity` providers and a provider interface.
- Engine/scene `version`: `Version.parse/compare/compatible` in `source/engine/core/version.lua`; `project.lua` and scene `settings.lua` may declare the engine version they target (format `1.0.0a`, `a` = alpha), the scene loader reports mismatches (`package.compatibility`) for the future launcher.
- Folder nodes: a scene node can be `nodes/<name>/init.lua` with sibling modules loaded through `require('scene.nodes.<name>.<part>')`.
- `source/engine/net`: authoritative Server and predicting Client (fixed tick, snapshots, reconciliation, interpolation, remote events/functions, relevance, client authority, LAN server list). See [multiplayer](guides/development/multiplayer.md).
- Plugin loader (`source/engine/plugins`) and the `pathfinding` plugin (`source/plugins/pathfinding`): A* on grids and waypoint graphs, smoothing, weights, path following. See [plugins](guides/development/plugins.md).
- `katsa.net`: UDP networking over ENet (`katsa_net` library). `listen`/`connect`, three channels (reliable, sequenced, unreliable), peer ping/loss, LAN server discovery (`katsa.net.lan`). See [networking](guides/katsa/net.md).
- `katsa.log` (levels log/warn/error, bounded history, listeners, `logs/latest.log`, print capture), JSON/CSV console export, crash reports as `crashes/crash-NN.log` with recent console lines. See [console and logs](guides/development/console.md).
- Workspace inspector: `Image.describe` mutated the parent class schema, so every `Frame`/`TextLabel` listed image fields (and the reverse looked like ImageLabel showing the wrong parameters). Each class now owns its schema, and writing a property the class does not declare is rejected (`Schema.hasProperty`). Focused suite: `--test-v108.4`.

## v108.3

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
