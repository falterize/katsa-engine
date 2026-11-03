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
| OpenAL Soft | `OpenAL32.dll` or `soft_oal.dll` | `libopenal.so.1` | `libopenal.1.dylib` | `libopenal.so` |
| FreeType | `freetype.dll` | `libfreetype.so.6` | `libfreetype.dylib` | `libfreetype.so` |
| katsa_native | `katsa_native.dll` | `libkatsa_native.so` | `libkatsa_native.dylib` | `libkatsa_native.so` |
| katsa_box2d (2D physics) | `katsa_box2d.dll` | `libkatsa_box2d.so` | `libkatsa_box2d.dylib` | `libkatsa_box2d.so` |
| katsa_net (networking, only when used) | `katsa_net.dll` | `libkatsa_net.so` | `libkatsa_net.dylib` | `libkatsa_net.so` |

`KATSA_LIB_DIR` points the loader at another directory. The libraries are **per platform and per CPU
architecture**: a `.dll` never works on Linux, an arm64 `.so` never on x86_64.

## Where every library comes from

| Library | Built by this repository? | Where to get it |
| --- | --- | --- |
| katsa_native, katsa_box2d, katsa_net | **Yes**: `python tools/native/build.py <target>` | Output in `build/native/<target>/`; or the `katsa-*` artifacts of the GitHub workflow `native.yml` (Actions tab) |
| SDL2 | No | Windows: `SDL2-2.30.x-win32-x64.zip` and Mac: `SDL2-2.30.x.dmg` from <https://github.com/libsdl-org/SDL/releases> (take `SDL2.dll` / `SDL2.framework/Versions/A/SDL2`). Linux: package `libsdl2-2.0-0` (apt) / `SDL2` (dnf, pacman) / `sdl2` (brew). Android: built from source by `android/prepare.py` |
| OpenAL Soft | No | Windows: `soft_oal.dll` (or `OpenAL32.dll`) from the `bin/Win64` folder of the zip at <https://openal-soft.org/#downloads>. Linux: `libopenal1` (apt) / `openal-soft`. macOS: `brew install openal-soft` and use its `libopenal.1.dylib`. Android: built from source by `android/prepare.py` |
| FreeType | No, optional (the built-in font renderer in `katsa_native` is used when absent) | Linux `libfreetype6`; Windows/macOS: any recent build |
| LuaJIT (static, only to build the host) | No | <https://github.com/LuaJIT/LuaJIT> branch `v2.1` (`git clone`, then `make`), or `libluajit-5.1-dev` on Debian/Ubuntu (`/usr`), `brew install luajit` on macOS |
| llvm-mingw (Windows cross compiler) | No | <https://github.com/mstorsjo/llvm-mingw/releases>, unpack and add `bin/` to `PATH` |
| Android NDK r26+ | No | <https://developer.android.com/ndk/downloads> or Android Studio > SDK Manager > SDK Tools > NDK |
| libjoltc (3D physics, Jolt) | Prebuilt, in `vendor/joltPhysics/native/` | Nothing to do on desktop (extracted at run time); Android copies it into the APK |

**Running from source on Windows** (`luajit tools/dev/katsa.lua`): compiled libraries are not stored in
Git. Put `katsa_native.dll`, `katsa_box2d.dll`, `katsa_net.dll`, `SDL2.dll` and `soft_oal.dll`
into `lib/` in the repository root. Without `katsa_native.dll` the start fails with
`Cannot load Katsa; tried: ...`; without `SDL2.dll` with `Cannot load SDL2; tried: ...`.

## Three outputs and how to package them

All platforms use the same packager, `tools/build/packageKatsa.py`:

| Output | Command |
| --- | --- |
| Game archive (run with `katsa Game.katsa`) | `python tools/build/packageKatsa.py --source <game folder> --output dist/Game.katsa` |
| Generic runtime executable | `python tools/build/packageKatsa.py --runtime-only --host build/native/<target>/katsa[.exe] --output dist/katsa[.exe]` |
| One fused file (game + runtime) | `python tools/build/packageKatsa.py --source <game folder> --host build/native/<target>/katsa[.exe] --output dist/Game[.exe]` |
| Whole repository as the game | `python tools/build/packageProject.py --output dist --host build/native/<target>/katsa` (`--with-validation` adds the tests) |

`validation/`, `docs/`, `tools/`, `native/` and third-party C sources are not packed. The fused
file must be shipped together with the libraries from the table above (next to it or in `lib/`).

## Step by step: Windows (.exe)

You need a Windows PC or Linux/macOS with llvm-mingw. The commands below are for Windows PowerShell.

1. Install Python 3.10+ and Git. Download **llvm-mingw** (`llvm-mingw-*-ucrt-x86_64.zip`), unpack it
   and add its `bin` folder to `PATH`. Check: `x86_64-w64-mingw32-clang --version`.
2. `git clone https://github.com/falterize/katsa-engine` and `cd katsa-engine`.
3. Build the project libraries: `python tools/native/build.py windows`. Result in
   `build\native\windows\`: `katsa_native.dll`, `katsa_box2d.dll`, `katsa_net.dll`. (A warning from
   `stb_vorbis` is harmless.)
4. Download `SDL2-2.30.x-win32-x64.zip` and take `SDL2.dll`; take `soft_oal.dll` from the OpenAL Soft
   zip (`bin\Win64`). Copy both next to the DLLs from step 3 (or into `lib\`).
5. Play from source: copy the five DLLs into `lib\`, then
   `luajit tools\dev\katsa.lua .` (needs `luajit.exe`; see the LuaJIT row above).
6. Optional, a standalone `katsa.exe`: build a Windows static LuaJIT
   (`make HOST_CC=gcc CROSS=x86_64-w64-mingw32- TARGET_SYS=Windows`), then set
   `LUAJIT_WIN_LIB=<...>\libluajit-5.1.a` and `LUAJIT_WIN_INCLUDE=<...>\src` and rerun step 3.
   `KATSA_GUI=1` builds it without a console window.
7. Package: `python tools/build/packageProject.py --output dist --host build\native\windows\katsa.exe`
   and ship `dist\Katsa-<version>` (rename to `.exe`) with the five DLLs next to it.

## Step by step: Linux

1. `sudo apt install build-essential clang python3 git libsdl2-2.0-0 libopenal1 xvfb` (Fedora: `dnf install clang
   SDL2 openal-soft`). `xvfb` is only needed for headless test runs.
2. Build LuaJIT: `git clone --depth 1 --branch v2.1 https://github.com/LuaJIT/LuaJIT && make -C LuaJIT && sudo make -C LuaJIT install`
   (prefix `/usr/local`) or choose `PREFIX=$HOME/lj` and export `LUAJIT_PREFIX=$HOME/lj`.
3. `export LUAJIT_PREFIX=/usr/local` (or your prefix) and run `python3 tools/native/build.py linux`.
   Result in `build/native/linux/`: the three `.so` files and the `katsa` host.
4. Run from source: `luajit tools/dev/katsa.lua .` (run it from the repository root).
5. Package one file: `python3 tools/build/packageProject.py --output dist --host build/native/linux/katsa`,
   then `cp build/native/linux/*.so dist/` and run `dist/Katsa-<version>`.
6. Tests: `tools/dev/runTests.sh --test-v108.5` and `luajit validation/tests/katsa/run.lua`.

## Step by step: macOS

Build on a Mac (the script uses Apple `clang`). It produces **universal** (x86_64 + arm64) `.dylib`
files; the host `katsa` is built for the architecture of your Mac.

1. `xcode-select --install`, then `brew install python luajit sdl2 openal-soft git`.
2. `git clone https://github.com/falterize/katsa-engine && cd katsa-engine`.
3. `export LUAJIT_PREFIX=$(brew --prefix luajit)`, then `python3 tools/native/build.py macos`.
   (`MACOSX_DEPLOYMENT_TARGET` defaults to 10.13. Homebrew's `libluajit-5.1.a` must exist; otherwise build
   LuaJIT yourself as in the Linux steps with `MACOSX_DEPLOYMENT_TARGET=11.0 make`.)
4. Copy the system libraries next to the result so the loader finds them:
   `cp $(brew --prefix sdl2)/lib/libSDL2.dylib build/native/macos/` and
   `cp $(brew --prefix openal-soft)/lib/libopenal.1.dylib build/native/macos/`.
5. Run from source: `luajit tools/dev/katsa.lua .`.
6. Package: `python3 tools/build/packageProject.py --output dist --host build/native/macos/katsa`, copy
   the `.dylib` files beside it (or into `lib/`, or an `.app` bundle's `Contents/Frameworks`).
7. On Apple Silicon an executable must be signed after the archive was appended:
   `codesign --force --sign - dist/Katsa-<version>`. Without a developer certificate the first start needs
   right-click > Open.

CI builds and unit-tests Linux and macOS on every run of `native.yml`; the macOS result has not been
run by the author on real hardware.

## Step by step: Android (.apk)

The project template is the folder `android/` (Gradle + SDL2). `libmain.so` is `katsa_host.c`; at
start it copies `assets/game.katsa` to internal storage (only when it changed), runs the Lua
runtime from it and forwards stdout/stderr to logcat (`adb logcat -s katsa`).

1. Install **Android Studio** (or the command line tools), then through *SDK Manager* the SDK Platform 34,
   *CMake 3.22.1* and the **NDK r26+**. Set `ANDROID_HOME` (the SDK) and `ANDROID_NDK_HOME`
   (e.g. `$ANDROID_HOME/ndk/26.3.11579264`). JDK 17 is required.
2. On a Linux or macOS machine with `git`, `make`, `gcc` and Python 3 (Windows: use WSL):
   `python3 android/prepare.py`. It
   - clones SDL2 2.30.9, OpenAL Soft 1.23.1 and LuaJIT 2.1 into `android/deps/`,
   - cross-builds a static LuaJIT per ABI,
   - runs `tools/native/build.py android` and copies `libkatsa_native.so`, `libkatsa_box2d.so`,
     `libkatsa_net.so` and `libjoltc.so` to `android/app/src/main/jniLibs/<abi>/`,
   - packs the game and the Lua runtime into `android/app/src/main/assets/game.katsa`.
   Use `--abis arm64-v8a` for a quick phone build, `--game <folder>` for your own game (default: this repository).
   `armeabi-v7a` (old 32-bit phones) additionally needs `gcc -m32` support on the build machine.
3. Build: `cd android`, `gradle wrapper --gradle-version 8.7` (once), then `./gradlew assembleDebug`. Or open the
   `android/` folder in Android Studio and press Run. SDL2 and OpenAL Soft are compiled by CMake as part
   of this step (the first build takes several minutes).
4. Install: `adb install -r app/build/outputs/apk/debug/app-debug.apk`.
5. After changing only game files rerun `python3 android/prepare.py --skip-deps`, then step 3.
6. Release: set your own `applicationId` in `android/app/build.gradle`, create a keystore and a `signingConfig`,
   then `./gradlew bundleRelease` (Play Store) or `assembleRelease`.

Screen size and speed: the APK renders at 720 px height and Android stretches it to the screen
(`<meta-data android:name="katsa.renderHeight">` in `AndroidManifest.xml`; `0` = native resolution, sharper
but much slower on mid-range GPUs). The UI is laid out in about 540 units of height, so touch targets stay
usable on phones; `KATSA_UI_SCALE=2 luajit tools/dev/katsa.lua .` previews a scale on desktop.

Notes: Jolt (3D physics) ships binaries for arm64 and arm only, so on an x86_64 emulator 3D physics
falls back to the Oimo backend. The save directory is the app's internal storage. The Android
template has not been built in the environment where it was written (no NDK/SDK there); the pieces
that could be checked were: the host's Android branch (compiled with stubbed SDL headers), the LuaJIT
cross-build variables, and the CMake configuration against the real SDL2 and OpenAL Soft sources.
Report problems from step 3 with the first error lines of the Gradle output.

## Status

The standalone runtime provides the whole `katsa.*` API the engine uses: window, input, filesystem
(directories, ZIP/`.katsa`, TAR, TAR.GZ, 7z), timer, data, math, utf8, event, graphics (OpenGL 3.3 /
GLES 3.0 through SDL2), image, sound (WAV and Ogg Vorbis), audio (OpenAL, silent fallback) and
physics (Box2D 2.3.1 built into `katsa_box2d`). Verified in the development sandbox: the Linux build
(libraries, host, fused executable, unit tests, `--test-v108.5`). Not verified on real hardware: Windows
host build, macOS, Android, GPU and audio output.
