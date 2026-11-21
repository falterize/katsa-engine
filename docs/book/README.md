# Katsa book

Read it from the first page to the last: every page ends with links to the previous and the next one. Chapters build on each other; the last ones are reference.

Start here: [Projects and scenes](projects.md)


## 1. First steps

Install the engine, run a project or a scene, and understand how a game is organised.

1. [Projects and scenes](projects.md)
2. [Getting started](../guides/development/gettingStarted.md)
3. [Running and building Katsa](../guides/katsa/building.md)
4. [Create an independent game](../guides/development/newGame.md)
5. [Framework and scenes](../guides/development/framework.md)
6. [Project conventions](../guides/architecture/conventions.md)
7. [Project architecture](../architecture.md)

## 2. Scenes and nodes

How a scene is laid out, how nodes live and how you write your own.

1. [Scene authoring](../guides/development/scenes.md)
2. [Nodes, hierarchy and lifecycle](../guides/development/nodeLifecycle.md)
3. [Node classes and naming](../guides/development/classSystem.md)
4. [Node authoring and API reference](../guides/development/nodeAuthoring.md)
5. [Scenes as prefabs](../guides/development/prefabs.md)
6. [Spatial transforms (v45)](../guides/development/spatialTransforms.md)
7. [Actors and worker threads](../guides/development/actors.md)
8. [Localization](../guides/development/localization.md)

## 3. User interface

Layout, text, images, scrolling, styling and world-space UI.

1. [Responsive UI](../guides/ui/uiLayout.md)
2. [Shared image component and viewport resolution](../guides/ui/images.md)
3. [Text rendering](../guides/ui/textRendering.md)
4. [TextBox](../guides/ui/textBox.md)
5. [ScrollFrame](../guides/ui/scrolling.md)
6. [UI modifiers](../guides/ui/uiModifiers.md)
7. [UIStyler plugin](../guides/ui/uiStyler.md)
8. [Independent worlds and ViewportFrame](../guides/ui/viewportFrame.md)
9. [TileMap](../guides/ui/tileMap.md)

## 4. Rendering

Cameras, lights, shadows, shaders, surfaces and render quality.

1. [Render quality](../guides/rendering/renderQuality.md)
2. [Camera3D projection](../guides/rendering/camera3D.md)
3. [Katsa v83 — Shared directional lights and physics debug](../guides/rendering/lighting.md)
4. [Shaders](../guides/rendering/shaders.md)
5. [SurfaceUI and Decal](../guides/rendering/surfaces.md)
6. [Post-processing](../guides/rendering/postProcessing.md)
7. [Beam3D and Trail3D](../guides/rendering/ribbons.md)
8. [Level of detail: LODGroup](../guides/rendering/lod.md)
9. [v70 rendering, particles, UI and audio](../guides/rendering/particlesShadows.md)
10. [Android shader link fix — v35 (retained in v36)](../guides/rendering/androidShaderFix.md)

## 5. Models and animation

Import models, play animations, blend them and solve inverse kinematics.

1. [Model import](../guides/import/modelImport.md)
2. [Models, opacity and surface materials — v64](../guides/import/models.md)
3. [Hierarchical models and skeleton animation](../guides/import/hierarchy.md)
4. [Blend shapes (Blender Shape Keys)](../guides/import/blendShapes.md)
5. [Mesh skin limits](../guides/rendering/skinLimits.md)
6. [Playing and Enabled](../guides/animation/playback.md)
7. [AnimationTree and retargeting](../guides/animation/animationTree.md)
8. [Ramp and Tween](../guides/animation/rampTween.md)
9. [Smoothing per-tick state](../guides/animation/stepValue.md)
10. [Inverse kinematics (`ik` plugin)](../guides/animation/ik.md)
11. [Ragdoll](../guides/animation/ragdoll.md)

## 6. Physics

2D and 3D physics, colliders, constraints and backends.

1. [2D physics and Camera2D](../guides/physics/physics2D.md)
2. [Hierarchy, UI and physics](../guides/physics/nodesPhysics.md)
3. [Collider3D and attachment constraints](../guides/physics/collidersConstraints.md)
4. [Editable and image-derived collision geometry](../guides/physics/pointColliders.md)
5. [Collision levels](../guides/physics/collisionLevels.md)
6. [Reaching the physics of a node](../guides/physics/nodeAccess.md)
7. [3D physics backends](../guides/physics/backends.md)
8. [Parallel physics](../guides/physics/parallel.md)
9. [2D and 3D particles](../guides/physics/particles2D.md)

## 7. Particles and audio

Particle systems and sound.

1. [ParticleEmitter3D](../guides/particles/api.md)
2. [Particle collisions and lighting](../guides/particles/collisionsLighting.md)
3. [Particle visibility and material composition — v69](../guides/particles/visibility.md)
4. [Sound nodes in v46](../guides/audio/audioNodes.md)
5. [SoundManager, AudioListener and AudioSource (v108.1)](../guides/audio/audioModules.md)

## 8. Input

Actions, input maps and gamepads.

1. [Scene-owned input actions](../guides/input/actions.md)
2. [InputMap: named actions](../guides/input/inputMap.md)
3. [Gamepads, vibration and gyro](../guides/input/gamepad.md)

## 9. Multiplayer

The network layer, replication and a complete sample.

1. [katsa.net: transport](../guides/katsa/net.md)
2. [Multiplayer (engine networking)](../guides/development/multiplayer.md)
3. [Node replication](../guides/development/replication.md)
4. [replicationLab](../guides/development/replicationLab.md)
5. [multiplayerCars: the networked sample scene](../guides/development/multiplayerCars.md)

## 10. Tools and workflow

Editors, plugins, debugging, profiling and tests.

1. [Workspace editor](../guides/editor/workspace.md)
2. [Level editor scene (`levelEditor`, v108.9)](../guides/development/levelEditor.md)
3. [Plugins](../guides/development/plugins.md)
4. [ImGui plugin](../guides/development/imgui.md)
5. [Console, logs and crash reports](../guides/development/console.md)
6. [Debug settings and error reports](../guides/development/debugging.md)
7. [Hot reload](../guides/development/hotReload.md)
8. [Statistics and history](../guides/development/statistics.md)
9. [Runtime performance](../guides/development/performance.md)
10. [Profiling and budgets](../guides/performance/profiling.md)
11. [Testing and build verification](../guides/development/testing.md)
12. [Repeatable validation](../guides/development/validation.md)

## 11. Reference

Saved data, platform layer, conventions, limits and licenses.

1. [Scene data: folders and files](../guides/development/persistence.md)
2. [Save data](../guides/development/saveData.md)
3. [Background execution and time scale](../guides/development/backgroundExecution.md)
4. [katsa runtime layer](../guides/katsa/platform.md)
5. [Windows: transparency and extra OS windows](../guides/katsa/windows.md)
6. [Public libraries](../guides/development/libraries.md)
7. [Code conventions](../guides/development/codeStyle.md)
8. [Current limitations](../guides/development/limitations.md)
9. [Dependencies and licenses](../guides/development/licenses.md)
10. [Stare Shooter scene](../guides/development/stareShooter.md)
