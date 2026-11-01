# Third-party dependencies

`vendor` stores third-party code and the exact artifacts used by this project. Keep upstream licenses, version pins and local-patch notes with each dependency. Project adapters belong in `source/engine`; build and verification tools belong in `tools/build`.

| Directory | Included content | Project integration |
| --- | --- | --- |
| `json/` | JSON library and license | Data/import tools |
| `box2d/` | Box2D 2.3.1 source and zlib license (one local patch: squared weld threshold in `b2PolygonShape.cpp`) | Built into `katsa_box2d` by `tools/native/build.py`; used by `source/katsa/physics` |
| `enet/` | ENet 1.3.18 sources (reliable UDP) and MIT license | Built into `katsa_net` by `tools/native/build.py`; used by `source/katsa/net` |
| `stb/` | `stb_image`, `stb_image_write`, `stb_truetype`, `stb_vorbis` and the stb license | Compiled into `katsa_native` by `tools/native/build.py` |
| `oimoPhysics/` | Generated Lua runtime, Haxe source, licenses and upstream/local-patch notes | `source/engine/physics/3d/backends/oimo/` |
| `joltPhysics/` | Pinned joltc header, generated FFI declarations, platform libraries, licenses and provenance | `source/engine/physics/3d/backends/jolt/` |

Oimo's `init.lua` is the runtime module generated from Haxe. Its `source/` directory is source code for rebuilding that module, rather than a second solver that runs alongside it. The local BVH and angular-velocity fixes are recorded in [UPSTREAM.md](oimoPhysics/UPSTREAM.md).

Jolt executes compiled native code through the joltc C API. The full Jolt C++ tree is not required to launch this game. The distribution includes the artifacts it actually loads and pins the upstream source versions needed to reproduce or replace them. See [Jolt provenance](joltPhysics/UPSTREAM.md) and [native build/platform notes](joltPhysics/README.md).

```text
vendor/
  json/
  box2d/
    Box2D/                    upstream sources
    LICENSE.txt
  enet/
    include/enet/, *.c, LICENSE.txt
  stb/
    stb_*.h, stb_vorbis.c, LICENSE
  oimoPhysics/
    init.lua
    source/                   Haxe source snapshot
    UPSTREAM.md, licenses
  joltPhysics/
    include/
      joltc.h                 pinned upstream C API
      joltc.ffi.h             generated single-precision LuaJIT declarations
    native/
      win-x64/joltc.dll
      linux-x64/libjoltc.so
      android-arm/libjoltc.so
      android-arm64/libjoltc.so
    provenance.json
    UPSTREAM.md, README.md, licenses
```

From the project source root:

```text
python tools/build/oimo/build.py --haxe /path/to/haxe
python tools/build/jolt/prepareNative.py
python tools/build/jolt/generateBindings.py --check
```

Haxe 4.3.7 is an external build tool. The legacy `tools/build/buildPhysics.py` command forwards to the categorized Oimo tool. `prepareNative.py --download` restores pinned Jolt libraries and verifies their hashes before replacing them; ordinary startup is offline.

Keep dependency upgrades separate from style-only edits. Do not reformat generated Lua, upstream Haxe, dependency headers or licenses with the first-party formatters.

## Built-in 2D solver

2D physics uses Box2D from the installed LÖVE 11.5 `love.physics` module. No
additional Box2D library or duplicate upstream source tree is distributed here.
First-party adaptation lives in `source/engine/physics/2d`. The existing Jolt and
Oimo artifacts remain pinned and live in their existing vendor categories.
