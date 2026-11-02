# 3D physics backends

The scene engine uses `source.engine.physics`. Each world selects `oimo`, `jolt` or `auto`; scene code continues to use Body3D, Collider3D, Attachment3D and Constraint3D.

## Selecting a scene's backend

The game scene factory accepts options without changing the global default:

```lua
local Game = require('source.game.runtime.game')
manager:switch(Game.new, 'animationPhysicsLab', {
    physicsBackend = 'jolt',
    physics = { workerThreads = 4, parallelThreshold = 64 },
})
```

`physicsBackend` accepts `jolt`, `oimo` or `auto`. The optional `physics` table
overrides example defaults such as units or worker policy; `physicsBackend` takes
precedence over `physics.backend`. Legacy third-argument sample-type strings still
work; options can then be passed as the fourth argument. Examples use
`scene:createPhysics(settings)` so scene options reach every physics example.
Only scenes creating physics instantiate a solver. Backend choices for successive
scenes are independent. Command-line/environment defaults remain effective when
the scene does not provide a backend.

For an engine-only world, create physics before adding Body3D nodes:

```lua
local World = require('source.engine.world.world')
local world = World.new(resources, nil, { physics = { backend = 'oimo' } })
-- Or: local world = World.new(resources); world:createPhysics({ backend = 'jolt' })
```

Existing `World.new(resources, lighting)` and direct `world.physics = Physics.new(...)`
remain supported. `createPhysics` rejects replacing an already configured world;
destroy/recreate a world to select another solver. Stats shows the actual backend
and any auto-fallback status; see [Stats history](../development/statistics.md).

```text
source/engine/physics/
  init.lua                    public facade assembly
  valueTypes.lua              stable Lua values, separate from solver selection
  internal/                   body properties, motion, queues, steps and queries
    queryPolicy.lua           shared query eligibility and callback safeguards
  constraints/
    inputs.lua                reusable input snapshots and revisions
    settings.lua              scene properties to joint settings
    distance.lua              shared Rope/Spring impulse policy
  backends/
    registry.lua              adapter selection and observable fallback
    oimo/
      driver.lua              Oimo solver and adapter contract
      bodies.lua              Lua body setup and Oimo inverse inertia
      colliders.lua           Lua geometry and shape filters
      contacts.lua            shared scene contact-event policy
      constraints.lua         Oimo joint creation
      compatibility.lua      Lua representations without creating a solver
      types.lua              entry point to the vendored Oimo library
    jolt/
      driver.lua              native world, stepping and resource ownership
      bodies.lua              body insertion/removal and synchronization
      bodyBridge.lua          historical raw-method compatibility
      bodyState.lua           reusable native snapshots and invalidation
      colliders.lua           native shapes, replacement and materials
      contacts.lua            native callbacks and queued contact events
      constraints.lua         native joints, motors and breaking
      queries.lua             native raycasts and broadphase AABB queries
      filters.lua             collision layers and group revisions
      nativeMath.lua          shared native conversions and motion enums
      library.lua             loading the pinned native dependency
      native/                 project-owned C contact bridge, job policy and platform builds
```

Third-party Jolt headers, generated FFI declarations, binaries, licenses and provenance are under `vendor/joltPhysics`, alongside `vendor/oimoPhysics`. The adapter files above are project code. See [dependency layout](../../../vendor/README.md).

`nodes/physics/3d/constraints3D.lua` (formerly `constraints.lua`, kept as an alias) resolves attachments, observes input changes and owns joint lifetime. Backend-specific configuration stays in the appropriate adapter. The old `physics/constraintInputs.lua` path remains a one-line compatibility import.

## Adapter contract

`registry.resolve(name)` returns the selected name, adapter class and an optional fallback reason. The class exposes `new(physics, settings)`. Its instance is `physics.adapter`, and `adapter.world` is also exposed as `physics.world`.

| Adapter method | Responsibility |
| --- | --- |
| `createBody(object, settings, scale)` | Create the compatible Lua body representation |
| `wrapBody(body)` | Connect body methods before insertion |
| `createColliderCandidate()` | Create a temporary body for replacement validation |
| `addCollider(body, collider)` | Construct compatible Lua geometry |
| `bindContact(body, shape)` | Bind scene events to the live owner |
| `refreshFilters(body)` | Update shape and solver filters |
| `prepareCollider(candidate)` | Validate the native representation before replacement |
| `rebuild(body, candidate)` | Adopt a prepared replacement |
| `applySettings(body, values)` | Apply changes to the native representation |
| `pointInverseMass(body, x, y, z)` | Evaluate translational and angular response |
| `createJoint(kind, a, b, settings)` | Construct a joint in the selected solver |
| `release()` | Release adapter-owned resources |

Worlds provide the existing subset of stepping, body/joint insertion/removal, gravity, solver iterations, raycasts, AABB queries and debug drawing. Oimo uses its original World; Jolt implements the subset used by this engine. This does not promise compatibility with arbitrary private methods of either upstream library.

Oimo intentionally has empty `wrapBody`, `prepareCollider`, `rebuild` and `applySettings` hooks: the common body API has already updated its only Lua representation. Jolt must also synchronize native state. Explicit hooks keep backend checks out of common scene code.

## Shared representations

Both adapters use `oimo/compatibility.lua` for Lua body/shape data, common events and geometry filters. It does not instantiate or step a solver. Only `oimo/driver.lua` creates an active Oimo simulation world. Jolt creates a native PhysicsSystem and a separate geometry-only Oimo mirror for debug draw; that mirror is never stepped.

`Physics.valueTypes` and the historical `Physics.backend` alias expose compatible Vec3/Mat3/config/limit-motor values. `physics.backendName` identifies the active solver. `physics.driver` remains a legacy Jolt diagnostic alias; common implementation code uses `adapter`.

Fully removing the Oimo representation would require replacement math types, debug geometry and exact sensor narrow phase. The present boundary preserves the existing scene API while allowing independent solver adapters.

## Lifetime and hot paths

- Body creation/removal, settings, poses and collider replacements are deferred during contact/query traversal. Candidates are validated before replacing live colliders.
- Collider revisions belong to Body3D. Replacement invalidates the constraint's local frame; unchanged inputs retain the existing joint.
- Scene contact events run after leaving the native solver. Lua callback errors are stored and raised after returning from C.
- The native procedure table and callbacks have strong references. Moving functions between modules must preserve this ownership.
- Callback-facing code and solver entry points stay outside JIT traces. On supported platforms Jolt uses native worker threads; native contacts are copied to Lua after Update returns. LuaJIT callbacks never run on workers. Other platforms retain synchronous dispatch.
- Hot-path arrays and snapshots are reused. Module installation happens at load time, not per frame.
- `Physics:release()` is idempotent and may defer until traversal completes. Invalid step settings fail before native allocation.
- QueryPolicy checks eligibility again after user filters because a filter may destroy the candidate body.

## Editing guide

Change scene contact policy in `oimo/contacts.lua`; change native listener behavior in `jolt/contacts.lua`. Add shared body properties through the observed-properties/body API, then implement adapter-specific synchronization where needed. Keep solver-specific features inside their adapter directory.

Use the [v101-based code style](../development/codeStyle.md). Vendor code and historical comparison fixtures keep their upstream/reference formatting. See [testing](../development/testing.md), [current limitations](../development/limitations.md) and [native packaging](../../../vendor/joltPhysics/README.md).

Backend files export named method tables and import their own dependencies. Drivers compose these tables with `core.extensions.apply`; no backend file exports an anonymous installer.


## Parallel execution

Windows x64 and Linux x64 include a project-owned native contact bridge under
`backends/jolt/native`. Its C source and compiled artifacts belong to the engine;
upstream joltc/Jolt remain pinned under `vendor/joltPhysics`. See the
[parallel physics guide](parallel.md) for configuration, ownership and rebuilding.

2D uses the separate `source.engine.physics.2d` integration; see the [2D physics guide](physics2D.md).
