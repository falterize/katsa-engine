# Getting started

Install LÖVE 11.5 and launch this source root with `love .`. The menu opens the example catalog. Select a lab to explore rendering, physics, animation, UI, audio or particles; each lab provides its own controls. Workspace inspects the running node tree and properties.

## Editing

Start with `source/game/data/project.lua` to select your game's first scene. The example selector is a testing scene and can be bypassed entirely. Every scene has `settings.lua`, a lifecycle-only `main.lua`, and mandatory `assets`, `nodes`, `systems` and `scripts` categories, with scene UI code under `scripts/ui`. Full scene implementations stay inside their own folders. System discovery and ordering are written directly inside each scene's `main.lua`. See [scene authoring](scenes.md) for hooks, private imports and archive structure. Reusable engine services belong in `source/engine`; common host phases live in `source/game/runtime/game/`.

`source/game/data/manifest.lua` registers resources. Put images, models, audio and GLSL in their corresponding `assets` categories. Keep model sidecars beside the model. Import/build helpers are grouped under `tools/import`, `tools/assets` and `tools/build`.

## Physics

Use `love . --physics-oimo` or `love . --physics-jolt` to select a solver explicitly. Without a flag, auto mode uses Jolt when available and otherwise Oimo. Stats identifies the active backend. The high-level Body3D/Collider3D/Constraint3D API is shared; private raw solver methods are not portable.

Windows x64 is tested. Linux and Android libraries are bundled but require validation on target hardware. Android may require native library packaging inside the APK; see the [Jolt dependency notes](../../../vendor/joltPhysics/README.md).

## Build and checks

Run `python tools/build/packageProject.py --output dist` to create a `.love`. See [testing](testing.md) for diagnostic commands and [code conventions](codeStyle.md) before changing modules. LÖVE is an external runtime and is not embedded in the archive.
