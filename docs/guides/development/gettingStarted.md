# Getting started

Follow [Running and building Katsa](../katsa/building.md) for your platform, then start the examples project with `luajit tools/dev/katsa.lua ../katsa-engine-examples` (from source; the engine alone has no scene to run, see [Projects and scenes](../../book/projects.md)). The menu opens the example catalog: type in the search box or pick tags to filter scenes. Select a lab to explore rendering, physics, animation, UI, audio or particles; each lab provides its own controls. Workspace inspects the running node tree and properties.

## Editing

Start with your project's `conf.lua` (`settings.startScene`) to select your game's first scene. The example selector is a testing scene and can be bypassed entirely. Every scene has `conf.lua`, a lifecycle-only `main.lua`, and mandatory `assets`, `nodes`, `systems` and `scripts` categories, with scene UI code under `scripts/ui`. Full scene implementations stay inside their own folders. System discovery and ordering are written directly inside each scene's `main.lua`. See [scene authoring](scenes.md) for hooks, private imports and archive structure. Reusable engine services belong in `source/engine`; common host phases live in `source/runtime/game/`.

There is no global resource manifest: a scene names the images it wants under short aliases in its `conf.lua` (`assets = { stone = { path = 'shared://textures/surfaces/stone.png', filter = 'nearest' } }`), or simply uses `scene://` and `shared://` paths. The engine provides one alias itself, `white`, a 1x1 plain-fill texture. Put images, models, audio and GLSL in their corresponding `assets` categories. Keep model sidecars beside the model. Import/build helpers are grouped under `tools/import`, `tools/assets` and `tools/build`.

## Physics

Use `katsa . --physics-oimo` or `katsa . --physics-jolt` to select a solver explicitly. Without a flag, auto mode uses Jolt when available and otherwise Oimo. Stats identifies the active backend. The high-level Body3D/Collider3D/Constraint3D API is shared; private raw solver methods are not portable.

Windows x64 and Linux are tested; macOS and Android builds still need validation on real hardware. Android may require native library packaging inside the APK; see the [Jolt dependency notes](../../../vendor/joltPhysics/README.md).

## Build and checks

Run `python tools/build/packageProject.py --output dist` to create a `.katsa` archive. See [testing](testing.md) for diagnostic commands and [code conventions](codeStyle.md) before changing modules. The runtime is not embedded in the archive unless you fuse it with a host executable (`--host`).

<!-- book:nav -->
---
**Katsa book** · chapter 1, First steps · page 3 of 8

[← conf.lua](../../book/conf.md) · [Contents](../../book/README.md) · [Running and building Katsa →](../katsa/building.md)
<!-- /book:nav -->
