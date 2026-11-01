# Parallel physics

The katsa runtime remains unchanged. Jolt performs a fixed simulation step with its
native job system. Windows x64 and Linux x64 include a small project-owned C bridge;
Oimo remains a Lua solver on the main thread. Linux is cross-compiled, not tested on
a Linux device; Android currently uses the original synchronous Jolt callback path.

```lua
local physics = require('source.engine.physics').new({
    backend = 'jolt',
    workerThreads = 4,
    parallelThreshold = 64,
})
```

`workerThreads` defaults to `min(4, max(1, processorCount - 1))`. Set it to `0` for
synchronous native dispatch; values 0..32 are accepted. `parallelThreshold` is the
minimum active rigid-body count for using the worker pool; default 64, `0` forces
parallel dispatch. Below the threshold the same world uses a native synchronous
queue. The pool is created only on the first qualifying step, then retained between steps.
Small worlds keep no unused worker pool. These choices do
not change fixedDelta, solver iterations, collision quality, CCD or interpolation.
An explicit positive thread count fails on platforms without a native bridge;
the default remains usable there with synchronous Jolt.

## Thread ownership

- Only Jolt jobs run on workers. The Lua state, node hierarchy, rendering, gameplay,
  queries and script events stay on the caller/main thread.
- Native contact callbacks resolve per-compound-child friction/restitution and
  reference-counted joint exclusions using native copies. Copies update only when
  bodies, colliders, materials or constraints change.
- Workers append contact snapshots to a mutex-protected, reusable C buffer. They
  never call Lua, store Lua pointers, or change scene nodes. Buffer allocation
  failure is reported after Update; events are not silently dropped.
- Update is a barrier: the caller waits for all Jolt jobs before reading bodies,
  processing begin/end events, applying deferred mutations or releasing resources.
  This is parallel solver execution, not an asynchronous one-frame-late simulation.
- Each world owns its metadata, event buffer and job systems. The listener is detached
  before destroying the system; all workers are joined before freeing bridge memory.
  Contact order across independent bodies can vary with scheduling.

The C procedure table has process lifetime. Its function addresses come from the
exact loaded joltc library, avoiding a second Jolt runtime or hard-coded library
search paths. Query callbacks remain synchronous Lua callbacks and retain the JIT
guards from the previous implementation.

## Measurement and tuning

`physics.stats.workerThreads` reports configured workers; `parallelStep` reports
whether the last step used the pool. `workerContactCallbacks` counts contact
snapshots received from non-caller threads. `nativeSolverMilliseconds` measures
the last Jolt Update; `solverMilliseconds` includes event collection, mirror/body
synchronization and native constraint checks across this frame's fixed steps.

Body state is read once per body and native-step epoch, using reusable snapshots.
Adapter setters invalidate snapshots immediately. Native stepping no longer
rebuilds every Lua mirror transform: shape AABB/transform consumers refresh their
body on demand, while debug drawing explicitly refreshes the mirror. Triggers,
collider replacement and body removal retain current geometry and velocities.
Lua mirrors are compatibility geometry, not a second running solver. Mutating
private native pointers directly bypasses adapter cache invalidation and is not
part of the supported public API.

Use `katsa . --benchmark-v105` for a CPU-only fixed-step comparison. Environment
variables `KATSA_BENCH_THREADS` and `KATSA_BENCH_BODIES` select the worker count and
body count. It uses three independent runs, 60 warm-up steps and 120 measured steps
per run, with sleeping explicitly disabled. Do not run concurrent benchmarks.
More workers are not always faster; test a representative scene on target hardware.

## Build and verify

Upstream headers and joltc binaries are unchanged in `vendor/joltPhysics`. Project
code is `source/engine/physics/3d/backends/jolt/native/bridge.c`; adjacent `jobs.lua`
contains FFI declarations and policy. Own binaries stay beside the bridge under
`win-x64` and `linux-x64`, rather than being represented as upstream vendor files.

Install the official Zig 0.13.0 compiler, then run from the project root:

```sh
python tools/build/jolt/buildBridge.py --compiler /path/to/zig --target all
python tools/build/jolt/buildBridge.py --verify
python tools/build/jolt/prepareNative.py
```

The build uses a baseline x64 CPU, optimized stripped output and the pinned
single-precision joltc C header. Linux targets glibc 2.17 and pthreads. The build
manifest records compiler version, flags, source/header hashes and binary hashes.
Rebuild every distributed target after changing the bridge or header. Zig and
formatters are development tools and are not bundled with the game.
