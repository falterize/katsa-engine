# katsa runtime layer

`source/katsa` is the engine's platform layer. The engine only talks to the global `katsa.*` API.

| Module | Folder | Content |
| --- | --- | --- |
| `katsa.filesystem`, `data`, `timer`, `math`, `window`, `keyboard`, `mouse`, `event`, `system` | `core/` | Virtual filesystem over directories and archives, hashing/encoding, clock, input |
| archives | `core/archive.lua`, `inflate.lua`, `sevenZip.lua`, `lzma.lua` | ZIP/`.katsa` (DEFLATE), TAR, 7z (stored, LZMA, LZMA2) |
| `katsa.graphics` | `graphics/` | State, transforms, canvases, shaders, meshes, fonts, sprite batches; one category per file |
| `katsa.audio`, `katsa.sound` | `audio/`, `sound.lua` | Sources, listener, effects; OpenAL driver with a silent fallback (`KATSA_AUDIO=null`) |
| `katsa.physics` | `physics/` | Box2D bindings: world, body, fixture, shape, joint, contact |
| platform | `platform/` | SDL2 window and GL context, headless EGL for tests and servers |
| host | `host/` | Program start for `katsa game.katsa` and for fused executables |

Platform notes: LuaJIT cannot run an FFI callback from compiled code, so the physics
methods that enter native code which may call Lua back (`World:update`, destroying bodies, fixtures
and joints) are excluded from the JIT. Box2D is built with `NDEBUG`; degenerate polygons become
Box2D's unit box instead of aborting the process.

## Targets

| Target | API | Used for |
| --- | --- | --- |
| `desktop` | OpenGL 3.3 core | Windows, Linux |
| `es` | OpenGL ES 3.0 | Android |

Both targets are validated in CI-style runs through Mesa llvmpipe: `luajit validation/tests/katsa/run.lua`.

## Headless platform

`source.katsa.platform.headlessEgl` creates an offscreen EGL context (surfaceless display, no window, no
config required) for dedicated servers, tests and tools.

```lua
local Headless = require('source.katsa.platform.headlessEgl')
local platform, reason = Headless.new('desktop') -- or 'es'
assert(platform, reason)
local address = platform:getProcAddress('glCreateShader')
platform:close()
```

A platform object exposes `target`, `getProcAddress(name)` and `close()`. Window backends (GLFW on
desktop, EGL on Android) implement the same three members plus presentation and input.

## Shader translation

`source.katsa.graphics.shaderTranslator.translate(source, { target = 'desktop' | 'es', renderTargets = n })`
turns a shader-dialect shader into separate vertex and pixel GLSL:

* One source holds both stages behind `#ifdef VERTEX` / `#ifdef PIXEL`, as in katsa. User code goes to the stage
  whose entry point (`vec4 position(...)`, `vec4 effect(...)`) it defines; the other stage uses the default.
* `varying`, `attribute`, `extern`, `Image`, `ArrayImage`, `CubeImage`, `VolumeImage`, `Texel` and `number`
  are supported. `#pragma language glsl1` additionally maps `texture2D`/`texture3D`/`textureCube`.
* Built-ins: `VertexPosition`, `VertexTexCoord`, `VertexColor` (locations 0..2), `TransformMatrix`,
  `ProjectionMatrix`, `TransformProjectionMatrix`, `NormalMatrix`, `ConstantColor`, `katsa_ScreenSize`,
  `katsa_PixelCoord`, `katsa_PointSize`, `katsa_VertexID`, `katsa_InstanceID`.
* Custom `attribute` declarations get explicit locations from 3 in declaration order; the result carries
  `attributes[name] = { location, type }` and `attributeOrder`, so the vertex layout never depends on driver
  queries.
* On `es` every stage declares `highp` defaults, which avoids vertex/pixel precision mismatches on GLES drivers.
  This replaces the former Android shader fix.
* `katsa_Canvases[]` (multiple render targets) declares `renderTargets` outputs (default 4).
* Errors return `nil, message`; driver compile errors are reported by `glShaderCheck`.

Not translated: gamma correction of vertex colors (the window backend will decide the colour space) and the
raw `void position()` / `void effect()` style.

## Verification

`validation/tests/katsa/run.lua` runs 109 checks: translator unit tests, plus every project shader compiled and
linked on both targets (included libraries and material hooks are exempt). Fifty-one shader variants produced
by the engine during `katsa . --test` were also compiled once on both targets without errors.
