# Katsa

A Lua 2D and 3D engine and interactive example collection on its own LuaJIT + OpenGL runtime (earlier versions used LÖVE as a wrapper): scene nodes, materials, lighting, shadows, animation, Box2D/Jolt/Oimo physics, particles, audio and 2D/world-space UI. Workspace provides runtime inspection and editing; scenes are authored in code.

## Run

Build the katsa runtime (see [building](docs/guides/katsa/building.md)) and run `katsa .` from this directory, or run a release `.katsa` archive. Optional flags: `--physics-jolt` or `--physics-oimo`. Auto mode prefers Jolt when its native library loads. Desktop VSync is disabled by default. Try `--scene abilityRunner2D` for the 2D runner with checkpoints, abilities and 8x8 pixel animation. Windows startup enables native DPI awareness with logical UI sizing; desktop geometry uses hardware-aware MSAA defaults. See the [quality guide](docs/guides/rendering/renderQuality.md) for resolution and sampling settings.

## Project layout

| Directory | Content |
| --- | --- |
| `source/engine/` | Reusable engine services and node APIs |
| `source/game/` | Self-contained scene folders, common runtime and game data |
| `validation/` | All tests: integration, performance, fixtures and versioned regression suites (`validation/tests/`) |
| `native/` | The project's C/C++ runtime sources (host, bindings, Box2D bridge) |
| `assets/` | Models, textures, shaders, audio and source assets |
| `vendor/` | Pinned third-party dependencies and licenses (Box2D, stb, Jolt, Oimo, json) |
| `tools/project/templates/game/` | Generator-only entry/configuration resources; scene code has one canonical source |
| `tools/` | Asset generation, importing, building and dependency verification |
| `docs/` | Current guides, architecture, changelog and reference images |

Select your game's first scene in `source/game/data/project.lua`. Each scene owns its settings, lifecycle-only `main.lua`, assets, nodes, systems and scripts, including `scripts/ui` for its interface code. `scripts/content.lua` composes content; other scripts and UI helpers are grouped by responsibility. Empty directories are preserved by the packers without marker files. The default menu is an example selector; it can be bypassed. System discovery/order/enabling is visible directly in each scene's `main.lua`.

Every World2D/World3D automatically owns an `Environment` with categorized Debug and particle settings. World3D also includes lighting, shadows, sky, fog and rendering categories. Both world dimensions select their view through `currentCamera`; cameras expose `fov`.

Camera3D supports Perspective and Orthographic projection (`fov`, `orthoSize`); see the [Camera3D guide](docs/guides/rendering/camera3D.md). Per-tick gameplay state is smoothed with [StepValue](docs/guides/animation/stepValue.md).

Collider3D GeometrySource accepts live model nodes or OBJ/GLB/glTF paths. Points remains available for editable collision geometry; getPointsFromModel/setPointsFromModel import independent coordinates and triangle topology. See the [collider guide](docs/guides/physics/collidersConstraints.md).

## Guides

- [2D/shared particles](docs/guides/physics/particles2D.md) and [debug settings / crash history](docs/guides/development/debugging.md)

- [TextBox input, editing shortcuts and runtime error reports](docs/guides/ui/textBox.md)

- [Create a clean game](docs/guides/development/newGame.md), [progress and preferences](docs/guides/development/persistence.md), and [repeatable validation](docs/guides/development/validation.md)

- [Node authoring and API](docs/guides/development/nodeAuthoring.md) and [node lifecycle](docs/guides/development/nodeLifecycle.md)
- [Getting started](docs/guides/development/gettingStarted.md) and [save data](docs/guides/development/saveData.md)
- [Scene folders, asset paths, systems and archives](docs/guides/development/scenes.md)
- [Mesh skin limits](docs/guides/rendering/skinLimits.md)
- [Stare Shooter: ported Godot scene, controls and customization](docs/guides/development/stareShooter.md)
- [Architecture](docs/architecture.md) and [code conventions](docs/guides/development/codeStyle.md)
- [Rendering](docs/guides/rendering/renderQuality.md), [UI](docs/guides/ui/uiLayout.md), [text and shared widgets](docs/guides/ui/textRendering.md) and [scrolling](docs/guides/ui/scrolling.md), [model import](docs/guides/import/modelImport.md)
- [2D physics, spatial groups, visual hierarchy, gravity and Camera2D](docs/guides/physics/physics2D.md), [editable colliders](docs/guides/physics/pointColliders.md)
- [Physics backends](docs/guides/physics/backends.md) and [parallel execution](docs/guides/physics/parallel.md), [particles](docs/guides/particles/api.md), [audio](docs/guides/audio/audioNodes.md)
- [Dependencies](vendor/README.md), [testing](docs/guides/development/testing.md) and [limitations](docs/guides/development/limitations.md)
- [Stats and metric history](docs/guides/development/statistics.md), including clickable plots and recent averages
- [Runtime performance](docs/guides/development/performance.md), including JIT cache policy and open-Stats profiling

Build an archive with `python tools/build/packageProject.py --output dist`. Project code is MIT; see [LICENSE](LICENSE) and the [asset/dependency notices](docs/guides/development/licenses.md).

Generated scenes expose `scene.data` for shared progress, preferences and arbitrary
text/binary files in persistent device storage. Keep the save identity stable
across updates. Starter Game is part of `source/game/scenes/starterGame`; run
`katsa . --scene starterGame` or select it in the menu. Its optional
`settings.lua.frameRateLimit` accepts `0` (uncapped) or a positive ceiling.

Use `scene.data:scope('shooter'):scope('extra')` or `scope('shooter/extra')` for
nested folders. `read/write` handles progress/preferences `.json` tables and raw
text/binary files through one API under `saves/`. Root `main.lua` and `conf.lua`
only install the shared engine bootstrap/window configuration; demo-only startup
adapters stay in `source/game/runtime/startup.lua`.
