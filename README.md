# Katsa
<img width="256" height="256" alt="Logo" src="https://github.com/user-attachments/assets/f4e0a692-4519-484c-9898-bfb491d6d54d" />

A Lua 2D and 3D engine and interactive example collection on its own LuaJIT + OpenGL runtime (earlier versions used LÖVE as a wrapper): scene nodes, materials, lighting, shadows, animation, Box2D/Jolt/Oimo physics, particles, audio and 2D/world-space UI. Workspace provides runtime inspection and editing; scenes are authored in code.

## Run

Full instructions for every platform (Windows, Linux, macOS, Android), packaging and
troubleshooting: **[Running and building Katsa](docs/guides/katsa/building.md)**.

Quick start from source:

1. Install Git, Python 3.10+, LuaJIT 2.1 and a C compiler (Windows: llvm-mingw; Linux: clang or gcc;
   macOS: Xcode command line tools).
2. Build the native libraries: `python tools/native/build.py windows` (or `linux`, `macos`).
3. Get SDL2 and OpenAL Soft: on Windows put `SDL2.dll` and `soft_oal.dll` into `lib\` together with
   the built DLLs; on Linux and macOS install them with the package manager.
4. Run the engine from this folder:

| Command | What starts |
| --- | --- |
| `luajit tools/dev/katsa.lua .` | Nothing to run: a black window and a console message. |
| `luajit tools/dev/katsa.lua path/to/scene` | One scene (folder or archive). |
| `luajit tools/dev/katsa.lua path/to/project` | A project: a folder or archive with a `conf.lua`. |

The engine ships no scenes. Clone [katsa-engine-examples](https://github.com/falterize/katsa-engine-examples)
next to it and run `luajit tools/dev/katsa.lua ../katsa-engine-examples`: the menu lists every example
scene, searchable by name and tags. Drop a scene or project on the window to switch to it. See
[Projects and scenes](docs/book/projects.md).

Useful flags: `--physics-jolt` or `--physics-oimo` (3D physics backend; auto prefers Jolt),
`--shared <folder>` (more `shared://` asset folders). See the
[quality guide](docs/guides/rendering/renderQuality.md) for resolution, VSync and sampling settings.

## Learn Katsa

The documentation is a book: **[start at the contents](docs/book/README.md)** and turn the pages
with the links at the bottom of each one. Chapters go from first steps through scenes and nodes, UI,
rendering, animation, physics, audio, input and multiplayer to tools and reference.

## Project layout

| Directory | Content |
| --- | --- |
| `source/engine/` | Reusable engine services and node APIs |
| `source/runtime/`, `source/devtools/` | The runtime any scene gets: Workspace, F4 debug menu, pause menu, catalog |
| `source/plugins/` | Optional features: `ik`, `pathfinding`, `uiStyler`, `ads`, `imgui` |
| `validation/` | All tests: integration, performance, fixtures and versioned regression suites (`validation/tests/`) |
| `native/` | The project's C/C++ sources: one folder per native library in `native/src` |
| `assets/` | Only what the engine itself needs: shaders, the default font, fallback textures, the click sound |
| `vendor/` | Pinned third-party dependencies and licenses (Box2D, stb, Jolt, Oimo, json) |
| `tools/` | Asset generation, importing, building, documentation and dependency verification |
| `docs/` | The [book](docs/book/README.md), architecture, instructions for AI agents (`docs/AGENTS.md`), changelog and images |

Every World2D/World3D automatically owns an `Environment` with categorized Debug and particle
settings. Both world dimensions select their view through `currentCamera`.

Build an archive with `python tools/build/packageProject.py --output dist`
([packaging](docs/guides/katsa/building.md#packaging-a-game)). Project code is MIT; see
[LICENSE](LICENSE) and the [asset/dependency notices](docs/guides/development/licenses.md).

## Credits

Katsa is built on the work of others. Each library keeps its own license next to its sources
(`vendor/`, `assets/fonts/engine`, `source/plugins/imgui/vendor`).

| Component | Author | Used for |
| --- | --- | --- |
| [LuaJIT](https://luajit.org/) | Mike Pall | the scripting runtime |
| [SDL2](https://libsdl.org/) | Sam Lantinga and contributors | window, input and the Android activity |
| [Box2D](https://github.com/erincatto/box2d) | Erin Catto | 2D physics |
| [Jolt Physics](https://github.com/jrouwe/JoltPhysics), [joltc](https://github.com/amerkoleci/joltc), [JoltPhysicsSharp](https://github.com/amerkoleci/JoltPhysicsSharp) | Jorrit Rouwe; Amer Koleci | 3D physics backend and its C API and binaries |
| [OimoPhysics](https://github.com/saharan/OimoPhysics) | Yuya Saito (saharan) | pure Lua 3D physics backend |
| [ENet](https://github.com/lsalzman/enet) | Lee Salzman | reliable UDP for `katsa.net` |
| [stb](https://github.com/nothings/stb) | Sean Barrett | image, TrueType and Ogg Vorbis decoding |
| [dr_libs](https://github.com/mackron/dr_libs) | David Reid | MP3 and FLAC decoding |
| [Dear ImGui](https://github.com/ocornut/imgui), [cimgui](https://github.com/cimgui/cimgui) | Omar Cornut; the cimgui contributors | the engine tool windows (`imgui` plugin) |
| [json.lua](https://github.com/rxi/json.lua) | rxi | JSON |
| [DejaVu Sans](https://dejavu-fonts.github.io/) | Bitstream, Inc. and the DejaVu authors (Stepan Roh and others) | the default UI font |

Assets of the example scenes (models, textures, music) and their credits live in the
[examples repository](https://github.com/falterize/katsa-engine-examples).
