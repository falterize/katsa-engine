# Current limitations

- Workspace is a runtime inspector/editor, not a scene serialization or Undo/Redo system. Scenes are authored in Lua.
- Rendering quality, shadows, resolution and large dynamic scenes can produce long frames. Disabled VSync does not guarantee stable 60 FPS or override OS/driver limits.
- Body colliders require an explicit rebuild after relevant size/scale changes. Supported rigid bodies use positive uniform scale at creation.
- Jolt and Oimo trajectories and constraint softness differ. Cone uses a 24-segment convex hull in Jolt; several constraint families map to SixDOF. Raw/private solver APIs are not interchangeable.
- Jolt parallel execution is provided by a project-owned C bridge on Windows x64 and Linux x64. Oimo remains single-threaded. Android retains synchronous Jolt until a matching bridge is built and packaged. Game events and rendering remain on the Lua/main thread.
- Windows x64 native loading and worker execution are tested. The Linux worker bridge is cross-compiled but not device-tested. Included Linux x64 and Android ARM/ARM64 binaries are hash-verified, not device-tested here. Android may require APK-native packaging; macOS and Windows ARM64 binaries are absent.
- Particles use Lua integration and optional budgeted raycasts through the selected backend. They do not have individual rigid bodies, particle-to-particle collisions or two-way impulses.
- World-space UI projects rectangular local bounds, not arbitrary curved/skinned surfaces. FBX requires external conversion; unsupported model extensions/material features may need baking or conversion.

See the [physics contract](../physics/backends.md), [model import guide](../import/modelImport.md) and [native packaging notes](../../../vendor/joltPhysics/README.md).

ScrollFrame supports both axes, canvas sizing and scrollbar insets. It does not implement Roblox network/Content objects, elastic overscroll or inertial scrolling. Disabled axes clamp to zero; wheel and drag input stop when scrollingEnabled is false.

## Persistence and standalone projects

The data-save API stores plain JSON progress/preferences, not live scenes or
Undo/Redo history. It uses a single writer per slot, verified sibling generations,
and explicit game-specific data validation. The standalone scene host supplies
engine resources and UI routing without example navigation. Games implement
their own menus, input bindings and gameplay systems. See [persistence](persistence.md)
and [new games](newGame.md).
