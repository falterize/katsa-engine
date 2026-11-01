# katsa runtime layer (v108.1 foundation)

`source/katsa` is the engine's own platform layer, replacing LÖVE step by step. v108.1 ships the
parts that can be fully verified without a display: the shader translator, the GL validation
helper and the headless EGL platform. Window, input, audio and 2D drawing arrive in later versions
behind the same interface.

## Targets

| Target | API | Used for |
| --- | --- | --- |
| `desktop` | OpenGL 3.3 core | Windows, Linux |
| `es` | OpenGL ES 3.0 | Android |

Both targets are validated in CI-style runs through Mesa llvmpipe: `luajit source/tests/katsa/run.lua`.

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
turns a LÖVE-dialect shader into separate vertex and pixel GLSL:

* One source holds both stages behind `#ifdef VERTEX` / `#ifdef PIXEL`, as in LÖVE. User code goes to the stage
  whose entry point (`vec4 position(...)`, `vec4 effect(...)`) it defines; the other stage uses the default.
* `varying`, `attribute`, `extern`, `Image`, `ArrayImage`, `CubeImage`, `VolumeImage`, `Texel` and `number`
  are supported. `#pragma language glsl1` additionally maps `texture2D`/`texture3D`/`textureCube`.
* Built-ins: `VertexPosition`, `VertexTexCoord`, `VertexColor` (locations 0..2), `TransformMatrix`,
  `ProjectionMatrix`, `TransformProjectionMatrix`, `NormalMatrix`, `ConstantColor`, `love_ScreenSize`,
  `love_PixelCoord`, `love_PointSize`, `love_VertexID`, `love_InstanceID`.
* Custom `attribute` declarations get explicit locations from 3 in declaration order; the result carries
  `attributes[name] = { location, type }` and `attributeOrder`, so the vertex layout never depends on driver
  queries.
* On `es` every stage declares `highp` defaults, which avoids vertex/pixel precision mismatches on GLES drivers.
  This replaces the former Android shader fix.
* `love_Canvases[]` (multiple render targets) declares `renderTargets` outputs (default 4).
* Errors return `nil, message`; driver compile errors are reported by `glShaderCheck`.

Not translated: gamma correction of vertex colors (the window backend will decide the colour space) and the
raw `void position()` / `void effect()` style.

## Verification

`source/tests/katsa/run.lua` runs 109 checks: translator unit tests, plus every project shader compiled and
linked on both targets (included libraries and material hooks are exempt). Fifty-one shader variants produced
by the engine during `love . --test` were also compiled once on both targets without errors.
