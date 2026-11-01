# Jolt native libraries

This dependency lives in `vendor/joltPhysics` as of v104.1. Platform binaries are
under `native/`; `include/joltc.h` is the upstream C API, and
`include/joltc.ffi.h` contains its generated LuaJIT declarations. Project adapters
remain in `source/engine/physics/3d/backends/jolt`. Run the commands below from the
project source root, not from this dependency directory.

The release uses upstream **single-precision** joltc libraries published in
JoltPhysicsSharp, pinned to commit `e468f1f30ef74726a799ceef1f8427fa39867e93`.
Exact download URLs, sizes and SHA-256 hashes are in `provenance.json`.
These are native libraries; no .NET runtime or C# execution is involved.

The C header is pinned to joltc commit
`2bbcf73b1bec261e0351814662922f1b4784454c`. Its CMake dependency is Jolt v5.6.0.
Windows x64 ABI and all used calls were exercised in LÖVE 11.5. Other supplied
binaries (Linux x64, Android ARM/ARM64) were integrity-checked, not executed here.
macOS and Windows ARM64 binaries are not included; auto mode uses Oimo there.

```
python tools/build/jolt/prepareNative.py
python tools/build/jolt/generateBindings.py --check
```

`prepareNative.py --download` restores exactly the pinned artifacts and verifies
the downloaded bytes before replacing a library. Normal game startup needs no
network. Desktop startup extracts its bundled library into a hash-specific
LÖVE save-directory cache and verifies its contents before loading.

For Android, include the supplied matching `libjoltc.so` in the APK's native
library directory (`lib/arm64-v8a/` or `lib/armeabi-v7a/`). The loader first tries
the application-packaged library. Recent Android versions may reject dlopen
from writable save storage. A stock Android LÖVE launcher is therefore **not**
guaranteed to load Jolt from a standalone .love. Auto fallback is observable in
Stats; explicit `--physics-jolt` reports failure instead of silently using Oimo.
LÖVE's rendering/runtime code does not need changes; packaging a matching ABI
library is separate from replacing LÖVE.

To build from source, obtain joltc at the pinned commit and use its upstream
CMake project with `JPH_BUILD_SHARED=ON`, `JPH_SAMPLES=OFF`, `JPH_TESTS=OFF`,
`DOUBLE_PRECISION=OFF`, then build Distribution. A C++17 compiler and CMake are
required. See https://github.com/amerkoleci/joltc. For older x64 CPUs, configure
the upstream USE_AVX/USE_AVX2/USE_SSE4_1/USE_SSE4_2 and related instruction-set
options for the intended hardware. A locally rebuilt binary has a different
hash and needs an updated provenance manifest before using the verifier.

The project-owned worker/contact bridge is in
`source/engine/physics/3d/backends/jolt/native`, separate from these upstream files.
On Windows x64 and Linux x64, it handles contact materials, exclusions and events
in C, allowing the native Jolt thread pool to execute safely. Lua consumes events
after the synchronous Update boundary. Platforms without a bridge retain the
single-caller callback job system. See
[parallel execution](../../docs/guides/physics/parallel.md) for configuration and
`python tools/build/jolt/buildBridge.py --verify` for bridge integrity checks.

MIT notices for joltc, Jolt Physics and JoltPhysicsSharp are included here.
