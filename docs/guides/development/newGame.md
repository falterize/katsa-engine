# Create an independent game

From the engine source directory, run:

```text
python tools/project/createProject.py ../MyGame --name my-game
katsa ../MyGame
```

The destination must not exist and must be outside the engine source directory.
The name accepts lowercase ASCII letters, digits and hyphens, starting with a
letter. Creation stages a complete project before publishing the directory.
It never overwrites an existing project.

The result contains the engine, pinned dependencies/licenses, required shared
rendering assets, build/run tools and one scene. It does not copy the example
browser, other gameplay scenes, their models/audio, or the historical test suites.
The existing project remains the canonical source for engine and example edits.

```text
MyGame/
  main.lua                        installs the reusable engine bootstrap
  conf.lua                        window and application identity
  source/
    engine/                       reusable engine, including saves and Stats
    game/
      data/project.lua            title, unique identity, start scene, shared assets
      scenes/start/
        settings.lua              scene metadata, physics, environment, asset aliases
        main.lua                  create/update/update3D/update2D/destroy only
        assets/                   models/textures/audio/shaders/fonts
        nodes/                    scene-specific custom node modules
        systems/simulation.lua    optional simulation and cube behavior
        scripts/content.lua       content composition and saved data
        scripts/ui/interface.lua  scene interface
  assets/                         shared rendering assets and empty content categories
  vendor/                         pinned dependencies and license notices
  tools/                          run and build helpers
```

All ten required scene categories exist, even when empty. ZIP packers preserve
them as directory entries; no `.keep` files are needed. Every project starts with
a distinct save identity (`katsa-<name>`), or the explicit `--identity` value.
Keep it stable across updates so saves survive folder/archive replacement.
Changing the title does not move saves. Two projects with the same identity share
the same LÖVE save directory.

## Change the scene

The example lives in the main project at `source/game/scenes/starterGame`.
Run `katsa . --scene starterGame` from the engine source directory, or choose
Starter Game in the scene menu. There is no separate ready-game folder to edit.
The generator copies this canonical scene to `source/game/scenes/start` only
when you explicitly create an independent game.

Scene `settings.lua.frameRateLimit` is optional: `0` is uncapped, and a positive
integer requests a frame ceiling. The scene file controls the chosen value. The loop waits until
the frame deadline, using a high-resolution blocking timer on supported Windows
versions and a checked portable fallback elsewhere. It does not busy-spin or
change VSync. A project default is supported by the standalone bootstrap; an
explicit scene setting overrides it. Short waits are not assumed to be exact.

Compose nodes in `scripts/content.lua` and UI in `scripts/ui/interface.lua`.
The example displays a rotating cube, a button that saves a score, and a saved
rotation preference. Press F3 for the shared clickable Stats/history/export UI.
It has no example selector, demonstration toolbar, Workspace or forced pause menu.
Add the engine tools explicitly if your own game needs them.

`main.lua` contains the system-directory enumeration and order/enabled settings.
It calls UI construction explicitly in `create`, then dispatches the existing
general, 3D and 2D update hooks. Disable `simulation` there to stop that system;
the host does not secretly step physics or nodes a second time.

The standalone host owns world, renderer, camera, UI, input routing, audio and
resource teardown. Scene state owns gameplay. It is selected by
`runtime = 'standalone'` and is also available for direct scene previews in the
example collection:

```text
katsa . --scene starterGame
```

The generated game's bootstrap loads its configured scene directly. Add another
scene by copying its folder/categories and changing `source/game/data/project.lua.startScene`, or
use `katsa . --scene source/game/scenes/another-scene`. Scene ZIP packages use the
same layout. Set `physics.backend` to `jolt`, `oimo` or `auto`; call
`scene:createPhysics()` in scene creation when physics is actually needed.
The example cube does not create a physics world unnecessarily.

Image/audio/model references can use `scene://...` and `shared://...`; the latter
resolves from `source/game/data/project.lua.sharedAssets`. See [scene packages](scenes.md),
[node authoring](nodeAuthoring.md) and [persistence](persistence.md).

## Verify and package

```text
katsa ../MyGame --smoke-test
cd ../MyGame
python tools/build/packageProject.py --output dist
```

The smoke test renders ten real frames, checks the runtime journal, releases
resources and exits. It is a startup check, not a replacement for game-specific
tests. `packageProject.py` produces a `.katsa` archive runnable with `katsa`;
the filename identifies the engine version and can be renamed for your game.
The generator does not create a Windows executable or change physics binaries.

Every scene can use `scene.data` for shared progress, preferences and text/binary
files. Named scopes share committed disk data across scenes and application runs.
See [persistence](persistence.md) for streaming, recovery and stable save identities.

## Shared startup and generator resources

Both the collection and generated games install `source.engine.scenes.bootstrap`.
The root `main.lua` only supplies project configuration and optional adapters.
Input, touch, focus, visibility, resize, draw/update, file drops, errors, shutdown,
frame pacing and smoke tests share the same implementation. The collection adds
its demo scene factory, manifest, legacy migration and test registry through
`source/game/runtime/startup.lua`. Those adapters are not copied into a new game.

`conf.lua` uses `source.engine.core.windowConfig` with `source/game/data/project.lua`.
Generated games copy this same wrapper; window configuration has one implementation.
Logical window dimensions and optional window overrides go in `Project.window`.

Generator-only resources live in `tools/project/templates/game`, not a root
`templates` folder. They contain only a tiny entry wrapper, initial project
metadata and the generated game's README. Scene code comes from the canonical
Starter folder; no second engine loop or copy of the scene is stored there.

## Scene runtime selection

In the example collection, `runtime = 'standalone'` selects the reusable engine
scene host: world, camera, renderer, UI, input, audio and lifecycle only. It does
not attach demonstration Workspace/Tools/navigation behavior. When runtime is
omitted, the collection uses its existing demonstration host; `kind = 'interface'`
selects the camera-free interface adapter. This field does not choose LuaJIT,
physics backend or frame rate. Generated games use the standalone host directly.
