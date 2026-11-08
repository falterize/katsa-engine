# Running and building Katsa

This guide takes you from a fresh clone to a running engine and a shippable game on Windows, Linux,
macOS and Android. Every command is meant to be run from the repository root.

- [How Katsa runs](#how-katsa-runs): the pieces and the three ways to start a game
- [Quick start](#quick-start-run-from-source): run from source in a few minutes
- [Windows](#windows), [Linux](#linux), [macOS](#macos), [Android](#android): complete steps per platform
- [Packaging a game](#packaging-a-game), [build.py reference](#buildpy-reference),
  [troubleshooting](#troubleshooting)

## How Katsa runs

The engine is Lua code (`source/`) on top of a small native layer:

| Piece | What it is | Who provides it |
| --- | --- | --- |
| LuaJIT | the Lua VM | `luajit` executable (development) or built into the Katsa host |
| Host `katsa` / `katsa.exe` | a tiny executable: LuaJIT plus the Lua runtime appended as a ZIP | built from `native/src/host` |
| `katsa_native` | UTF-8 files, image, Ogg Vorbis and font decoding | built from `native/src/native` |
| `katsa_box2d` | 2D physics (Box2D) | built from `native/src/box2d` + `vendor/box2d` |
| `katsa_net` | networking (ENet) | built from `native/src/net` + `vendor/enet` |
| `katsa_threads` | worker threads for the Actor node | built from `native/src/threads` |
| SDL2 | window, OpenGL context, input | downloaded (see each platform) |
| OpenAL Soft | audio | downloaded |
| FreeType (optional) | alternative font renderer | downloaded; the built-in one is used when absent |
| Jolt (`joltc`) | 3D physics | prebuilt in `vendor/joltPhysics/native/`, nothing to do |

Native libraries are **per platform and per CPU architecture**: a `.dll` never works on Linux, an
arm64 `.so` never on x86_64. The engine looks for them in this order: the folder in the environment
variable `KATSA_LIB_DIR`, the executable's folder, `lib/` next to the executable, and when running
from source also `build/native/<platform>/`.

There are three ways to start a game:

| Way | Command | When |
| --- | --- | --- |
| From source | `luajit tools/dev/katsa.lua .` | developing: edit Lua, restart, no host build needed |
| Generic runtime | `katsa <game folder or .katsa>` | one installed engine, several games |
| Fused executable | `MyGame.exe` | shipping one file (plus the libraries) |

A `.katsa` file is a plain ZIP of the game folder. Folders, `.katsa`/`.zip` archives and fused
executables behave the same. Useful flags: `--scene <id>` starts a scene directly (ids are in
`source/game/sceneCatalog.lua`), `--physics-jolt` / `--physics-oimo` pick the 3D physics backend,
`--test-<name>` runs a test suite (see [testing](../development/testing.md)).

## Quick start (run from source)

1. Install **Git**, **Python 3.10+** and **LuaJIT 2.1** (`luajit` on `PATH`; Windows: see step 1 of
   [Windows](#windows)).
2. `git clone https://github.com/falterize/katsa-engine` and `cd katsa-engine`.
3. Get the native libraries for your platform: build them (`python tools/native/build.py <platform>`,
   see your platform below) and add SDL2 and OpenAL Soft.
4. `luajit tools/dev/katsa.lua .` opens the scene menu.

## Windows

The commands are for **PowerShell** in the repository folder. PowerShell runs programs from the
current folder only with a `.\` prefix: `.\dist\katsa.exe`, not `dist\katsa.exe`.

### 1. Tools

| Tool | Where | Check |
| --- | --- | --- |
| Git, Python 3.10+ | <https://git-scm.com>, <https://python.org> (or the Microsoft Store) | `python --version` |
| llvm-mingw (C/C++ compiler) | <https://github.com/mstorsjo/llvm-mingw/releases>: `llvm-mingw-<date>-ucrt-x86_64.zip`, unpack, add its `bin` folder to `PATH` | `x86_64-w64-mingw32-clang --version` |
| LuaJIT (`luajit.exe`, only to run from source) | build it ([step 5](#5-optional-build-katsaexe)) or take any LuaJIT 2.1 build for Windows | `luajit -v` |

### 2. Build the project libraries

```powershell
python tools\native\build.py windows
```

Result in `build\native\windows\`: `katsa_native.dll`, `katsa_box2d.dll`, `katsa_net.dll`,
`katsa_threads.dll`. A warning from `stb_vorbis` is harmless. To rebuild only some of them, name them:
`python tools\native\build.py windows net threads` ([reference](#buildpy-reference)).

### 3. Add SDL2 and OpenAL Soft

- SDL2: `SDL2-2.30.x-win32-x64.zip` from <https://github.com/libsdl-org/SDL/releases>, take `SDL2.dll`.
- OpenAL Soft: the zip from <https://openal-soft.org/#downloads>, take `bin\Win64\soft_oal.dll`.

Put both into `lib\` in the repository root.

### 4. Run from source

```powershell
copy build\native\windows\*.dll lib\
luajit tools\dev\katsa.lua .
```

`lib\` now holds six DLLs: the four from step 2, `SDL2.dll` and `soft_oal.dll`.

### 5. Optional: build katsa.exe

The host links LuaJIT statically, so it needs a Windows `libluajit` built with the same compiler.

1. Get the LuaJIT sources: `git clone --branch v2.1 --depth 1 https://github.com/LuaJIT/LuaJIT C:\katsa-luajit\LuaJIT`.
2. Build the static library. LuaJIT's build needs `make`, which llvm-mingw does not include. Either
   - on Linux / WSL with llvm-mingw:
     `make -C LuaJIT HOST_CC=gcc CROSS=x86_64-w64-mingw32- TARGET_SYS=Windows BUILDMODE=static amalg`, or
   - on Windows with a `make` (for example `winget install ezwinports.make`):
     `make -C C:\katsa-luajit\LuaJIT CC=x86_64-w64-mingw32-clang BUILDMODE=static`
     (this variant has not been tried by the maintainers).

   The result is `LuaJIT\src\libluajit.a`; `LuaJIT\src\luajit.exe` is a working `luajit` for step 4.
3. Build the host:

   ```powershell
   $env:LUAJIT_WIN_LIB = "C:\katsa-luajit\LuaJIT\src\libluajit.a"
   $env:LUAJIT_WIN_INCLUDE = "C:\katsa-luajit\LuaJIT\src"
   python tools\native\build.py windows host
   ```

   Result: `build\native\windows\katsa.exe`. Set `$env:KATSA_GUI = "1"` before the build for an
   executable without a console window. The host exports LuaJIT's C API (the Actor worker threads
   need it); `build.py` adds the linker flag.
4. Make it a runtime and run the repository with it:

   ```powershell
   python tools\build\packageKatsa.py --runtime-only --host build\native\windows\katsa.exe --output dist\katsa.exe
   mkdir dist\lib -Force
   copy lib\*.dll dist\lib\
   .\dist\katsa.exe .
   ```

Folder names may contain any characters (for example Cyrillic or Japanese): the host hands paths to
Lua as UTF-8 and DLLs are loaded through the Unicode Windows API.

## Linux

1. Packages: `sudo apt install build-essential clang python3 git libsdl2-2.0-0 libopenal1`
   (Fedora: `sudo dnf install clang SDL2 openal-soft`). Add `xvfb` for headless test runs.
2. LuaJIT: `git clone --depth 1 --branch v2.1 https://github.com/LuaJIT/LuaJIT && make -C LuaJIT && sudo make -C LuaJIT install`
   (installs to `/usr/local`; with `PREFIX=$HOME/lj` export `LUAJIT_PREFIX=$HOME/lj` instead).
3. Build everything, host included:

   ```sh
   export LUAJIT_PREFIX=/usr/local
   python3 tools/native/build.py linux
   ```

   Result in `build/native/linux/`: four `.so` files and the `katsa` host.
4. Run from source: `luajit tools/dev/katsa.lua .`
5. Run through the host: `python3 tools/build/packageKatsa.py --runtime-only --host build/native/linux/katsa --output dist/katsa`,
   copy `build/native/linux/*.so` to `dist/lib/`, then `dist/katsa .`.
6. Tests: `tools/dev/runTests.sh --test-v108.7`, or `xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7`
   without a display. After changing `native/src/threads`, also run `sh validation/native/threadsStress.sh`.

## macOS

Build on a Mac (Apple `clang`). Libraries are **universal** (x86_64 + arm64); the host is built for the
architecture of the Mac that builds it.

1. `xcode-select --install`, then `brew install python luajit sdl2 openal-soft git`.
2. `export LUAJIT_PREFIX=$(brew --prefix luajit)`, then `python3 tools/native/build.py macos`.
   (`MACOSX_DEPLOYMENT_TARGET` defaults to 10.13. If Homebrew has no `libluajit-5.1.a`, build LuaJIT as
   in the Linux steps with `MACOSX_DEPLOYMENT_TARGET=11.0 make`.)
3. Copy the system libraries next to the result:
   `cp $(brew --prefix sdl2)/lib/libSDL2.dylib build/native/macos/` and
   `cp $(brew --prefix openal-soft)/lib/libopenal.1.dylib build/native/macos/`.
4. Run from source: `luajit tools/dev/katsa.lua .`
5. Package as in [Packaging a game](#packaging-a-game) with `--host build/native/macos/katsa`, put the
   `.dylib` files beside it (or in `lib/`, or an `.app` bundle's `Contents/Frameworks`).
6. On Apple Silicon sign the executable after the archive was appended:
   `codesign --force --sign - dist/MyGame`. Without a developer certificate the first start needs
   right-click > Open.

The macOS build is compiled and unit-tested by the `native.yml` workflow but has not been run on real
hardware by the maintainers.

## Android

The project template is the folder `android/` (Gradle + SDL2). `libmain.so` is the host
(`native/src/host`); at start it copies `assets/game.katsa` to internal storage (only when it
changed), runs the Lua runtime from it and forwards stdout/stderr to logcat (`adb logcat -s katsa`).

1. Install **Android Studio** (or the command line tools), then in *SDK Manager*: SDK Platform 34,
   *CMake 3.22.1* and the **NDK r26+**. Set `ANDROID_HOME` (the SDK) and `ANDROID_NDK_HOME`
   (for example `$ANDROID_HOME/ndk/26.3.11579264`). JDK 17 is required.
2. On Linux or macOS with `git`, `make`, `gcc` and Python 3 (Windows: use WSL):
   `python3 android/prepare.py`. It
   - clones SDL2 2.30.9, OpenAL Soft 1.23.1 and LuaJIT 2.1 into `android/deps/`,
   - cross-builds a static LuaJIT per ABI,
   - runs `tools/native/build.py android` and copies the Katsa libraries and `libjoltc.so` to
     `android/app/src/main/jniLibs/<abi>/`,
   - packs the game and the Lua runtime into `android/app/src/main/assets/game.katsa`.

   `--abis arm64-v8a` builds for modern phones only (faster); `--game <folder>` packs your own game
   (default: this repository). `armeabi-v7a` additionally needs `gcc -m32` on the build machine.
3. Build: `cd android`, then `./gradlew assembleDebug` (`gradlew.bat` on Windows), or open `android/`
   in Android Studio and press Run. The first build compiles SDL2 and OpenAL Soft (several minutes).
4. Install: `adb install -r app/build/outputs/apk/debug/app-debug.apk`.
5. After changing only game files: `python3 android/prepare.py --skip-deps`, then step 3.
6. Release: set your own `applicationId` in `android/app/build.gradle`, create a keystore and a
   `signingConfig`, then `./gradlew bundleRelease` (Play Store) or `assembleRelease`.

**Windows without WSL**: the only step that needs `make`/`gcc` is the static LuaJIT. Download the
`katsa-android-luajit` artifact of the latest `native` workflow run, unpack it into
`android/deps/luajit/` (so `android/deps/luajit/arm64-v8a/lib/libluajit-5.1.a` exists), then
`python android/prepare.py --abis arm64-v8a` and `android\gradlew.bat assembleDebug`.

Screen size and speed: the APK renders at 720 px height and Android scales it to the screen
(`<meta-data android:name="katsa.renderHeight">` in `AndroidManifest.xml`; `0` = native resolution,
sharper but slower on mid-range GPUs). The UI is laid out in about 540 units of height;
`KATSA_UI_SCALE=2 luajit tools/dev/katsa.lua .` previews a scale on desktop. Jolt ships arm64 and arm
binaries only, so an x86_64 emulator uses the Oimo backend for 3D physics.

## Packaging a game

All platforms use one packager, `tools/build/packageKatsa.py`:

| Output | Command |
| --- | --- |
| Game archive (run with `katsa Game.katsa`) | `python tools/build/packageKatsa.py --source <game folder> --output dist/Game.katsa` |
| Generic runtime | `python tools/build/packageKatsa.py --runtime-only --host build/native/<platform>/katsa[.exe] --output dist/katsa[.exe]` |
| One fused file (game + runtime) | `python tools/build/packageKatsa.py --source <game folder> --host build/native/<platform>/katsa[.exe] --output dist/Game[.exe]` |
| Whole repository as the game | `python tools/build/packageProject.py --output dist --host build/native/<platform>/katsa[.exe]` (`--with-validation` adds the tests) |
| `.blend` models converted at packaging time | add `--convert-blend` (needs Blender on the build machine) |

Ship the executable together with the native libraries of its platform, next to it or in `lib/`.
`validation/`, `docs/`, `tools/` and `native/` are never packed.

## build.py reference

```
python tools/native/build.py <target> [library ...]
```

| Argument | Meaning |
| --- | --- |
| `<target>` | `windows`, `linux`, `macos` or `android` |
| no library | build all libraries; the host only when its LuaJIT variable is set |
| `katsa_native`, `katsa_box2d`, `katsa_net`, `katsa_threads`, `host` | build only these |
| `net`, `katsa_net.c`, `--katsa_net.c` | the same as `katsa_net` (prefix and extension are optional) |
| a source file name (`font.c`, `joint.cpp`, `lan.c`, `actor.c`) | the library that file belongs to |

| Environment variable | Used for |
| --- | --- |
| `LUAJIT_WIN_LIB`, `LUAJIT_WIN_INCLUDE` | the Windows host: static `libluajit.a` and the folder with `lua.h` |
| `LUAJIT_PREFIX` | the Linux/macOS host: LuaJIT install with `lib/libluajit-5.1.a` |
| `KATSA_GUI=1` | Windows host without a console window |
| `ANDROID_NDK_HOME` | Android builds |
| `MACOSX_DEPLOYMENT_TARGET` | oldest macOS version (default 10.13) |

The last line printed lists the libraries actually built; a skipped host says which variable is
missing. Output: `build/native/<target>/` (Android: `build/native/android/<abi>/`).

Source layout: `native/src/` has one folder per library (`native/`, `box2d/`, `net/`, `threads/`,
`host/`) and `common/export.h`. Each folder starts with a header or file comment that lists its files
and its conventions (units, ownership, threads). Third-party code stays in `vendor/`.

## Troubleshooting

| Message or symptom | Cause and fix |
| --- | --- |
| `Cannot load Katsa; tried: ...` | `katsa_native` is missing for this platform: build it (step 2) and put it into `lib/` |
| `Cannot load SDL2; tried: ...` | `SDL2.dll` / `libSDL2` missing next to the executable or in `lib/` |
| PowerShell: `The term 'dist\katsa.exe' is not recognized` or `module 'dist' could not be loaded` | run it as `.\dist\katsa.exe` |
| `No game to run` | pass a game: `katsa .` (folder), `katsa Game.katsa`, or use a fused executable |
| Actor scenes show "main thread" | `katsa_threads` is missing, or `katsa.exe` was built before v108.7 (did not export the Lua C API): rebuild both |
| `Blender was not found` | a `.blend` model needs Blender 3.6+ (or `KATSA_BLENDER=<path>`); shipped games use `--convert-blend` |
| `make: command not found` while building LuaJIT on Windows | see [Windows step 5](#5-optional-build-katsaexe): use WSL or install a `make` |
| Audio is silent but everything else works | OpenAL Soft is missing; the engine falls back to silence instead of failing |
| Crash reports | the error screen saves `last-error.txt` and a crash history in the save folder (`%APPDATA%\Katsa\katsa-engine` on Windows); see [console and logs](../development/console.md) |

## Status

The runtime provides the whole `katsa.*` API the engine uses: window, input, filesystem (folders,
ZIP/`.katsa`, TAR, TAR.GZ, 7z), timer, data, math, utf8, event, graphics (OpenGL 3.3 / GLES 3.0 through
SDL2), image, sound (WAV and Ogg Vorbis), audio (OpenAL, silent fallback), physics and threads.
Verified by the maintainers: Linux (libraries, host, packaged executables, test suites) and Windows
(libraries and `katsa.exe` on the owner's PC). Not yet verified on real hardware: macOS and the
Android APK build.
