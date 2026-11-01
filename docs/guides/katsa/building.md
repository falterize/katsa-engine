# Building and running Katsa

Katsa runs on its own runtime: a small C host (`katsa` / `katsa.exe`) that embeds LuaJIT and
reads one appended ZIP archive. SDL2 provides the window, GL context and input; OpenAL Soft,
FreeType and `katsa_native` are loaded at run time.

## Three ways to run a game

| Way | Command | When |
| --- | --- | --- |
| Development | `luajit tools/dev/katsa.lua <game folder>` (run from the repository root) | Editing Lua, no host build needed |
| Generic runtime | `katsa game.katsa` (also a folder, `.zip`) | Several games, one installed engine |
| Fused executable | `./MyGame` / `MyGame.exe` | Shipping one file |

A `.katsa` file is a plain ZIP of the game folder. It can hold any number of scenes and
sub-folders (the packager stores empty folders too). Scenes are ordinary files, so scene
switching works the same in a folder, a `.katsa` and a fused executable.

## Libraries that must sit next to the executable (or in `lib/`)

| Library | Windows | Linux | macOS | Android |
| --- | --- | --- | --- | --- |
| SDL2 | `SDL2.dll` | `libSDL2-2.0.so.0` | `libSDL2.dylib` | `libSDL2.so` |
| OpenAL Soft | `OpenAL32.dll` | `libopenal.so.1` | `libopenal.dylib` | `libopenal.so` |
| FreeType | `freetype.dll` | `libfreetype.so.6` | `libfreetype.dylib` | `libfreetype.so` |
| katsa_native | `katsa_native.dll` | `libkatsa_native.so` | `libkatsa_native.dylib` | `libkatsa_native.so` |

`KATSA_LIB_DIR` points the loader at another directory.

## Build steps

1. **katsa_native** (any target): `python tools/native/build.py <linux|windows|macos|android>`.
   Output: `build/native/<target>/`. Needs clang or gcc; Windows needs llvm-mingw
   (`x86_64-w64-mingw32-clang`); Android needs `ANDROID_NDK_HOME`; macOS must run on a Mac.
   The GitHub workflow `native.yml` builds them all.
2. **Host executable.** Set `LUAJIT_PREFIX` (Linux/macOS: a LuaJIT 2.1 install with `include/luajit-2.1`
   and `lib/libluajit-5.1.a`) and rerun the build script; it also writes `build/native/linux/katsa`.
   Windows: build LuaJIT with `make HOST_CC=gcc CROSS=x86_64-w64-mingw32- TARGET_SYS=Windows`,
   set `LUAJIT_WIN_LIB` to the resulting `libluajit-5.1.a` and `LUAJIT_WIN_INCLUDE` to its `src`
   directory, then run `build.py windows` to get `katsa.exe`. Set `KATSA_GUI=1` for a build without a console window.
3. **Package.**
   - Generic runtime: `python tools/build/packageKatsa.py --runtime-only --host build/native/windows/katsa.exe --output dist/katsa.exe`
   - Game archive: `python tools/build/packageKatsa.py --source <game folder> --output dist/Game.katsa`, then `katsa.exe Game.katsa`. `validation/` is omitted; `packageProject.py --with-validation` includes it.
   - Game and engine in one file: `python tools/build/packageKatsa.py --source <game folder> --host build/native/windows/katsa.exe --output dist/Game.exe`
4. Copy the libraries from the table beside the result.

## Linux and macOS

Same steps with `linux` / `macos`. On macOS use a universal LuaJIT build (set
`MACOSX_DEPLOYMENT_TARGET=11.0`) and ship the `.dylib` files in `lib/` or inside an `.app`
bundle's `Contents/Frameworks`.

## Android (.apk)

The runtime is prepared for it (GLES 3.0 context, `Native.os() == 'Android'`, per-ABI library
names), the APK project template comes in a later version. The plan: the standard SDL2 Android
project, `katsa_host.c` compiled into `libmain.so` with its `main` as the SDL entry, the fused
ZIP placed in `assets/game.katsa` (read through `SDL_RWops`), and `katsa_native.so` per ABI
from `build.py android`. Until then, the Android pieces that exist are the library build and the
platform code.

## Status

The standalone runtime provides the whole `katsa.*` API the engine uses: window, input, filesystem
(directories, ZIP/`.katsa`, TAR, TAR.GZ, 7z), timer, data, math, utf8, event, graphics (OpenGL 3.3 /
GLES 3.0 through SDL2), image, sound (WAV and Ogg Vorbis), audio (OpenAL, silent fallback) and
physics (Box2D 2.3.1 built into `katsa_box2d`). The engine suite (`katsa . --test`) passes on it.
Not verified on real hardware here: Windows host build, macOS, Android, GPU and audio output.
