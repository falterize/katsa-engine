#!/usr/bin/env python3
"""Prepares the Android project: third-party sources, per-ABI libraries and the game archive.

    export ANDROID_NDK_HOME=/path/to/android-ndk-r26d
    python3 android/prepare.py                       # whole engine as the game, arm64-v8a + x86_64
    python3 android/prepare.py --game path/to/game   # your own game folder (must contain main.lua)
    python3 android/prepare.py --abis arm64-v8a      # fewer ABIs build faster
    python3 android/prepare.py --skip-deps           # only refresh game.katsa

Steps (each one is skipped when its output already exists):
  1. clone SDL2, OpenAL Soft and LuaJIT into android/deps/ (pinned tags, needs git and internet);
  2. cross-build a static LuaJIT per ABI with the NDK (needs make and a host C compiler;
     armeabi-v7a also needs 32-bit host support: gcc -m32);
  3. build katsa_native, katsa_box2d and katsa_net per ABI (tools/native/build.py android) and copy
     them, plus libjoltc.so, to android/app/src/main/jniLibs/<abi>/;
  4. pack the game with the Lua runtime into android/app/src/main/assets/game.katsa.
Then build the APK:  cd android && gradle assembleDebug   (see docs/guides/katsa/building.md).
"""

import argparse
import os
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
DEPS = HERE / 'deps'
JNI = HERE / 'app' / 'src' / 'main' / 'jniLibs'
ASSETS = HERE / 'app' / 'src' / 'main' / 'assets'

SOURCES = {
    'SDL2': ('https://github.com/libsdl-org/SDL.git', 'release-2.30.9'),
    'openal-soft': ('https://github.com/kcat/openal-soft.git', '1.23.1'),
    'LuaJIT': ('https://github.com/LuaJIT/LuaJIT.git', 'v2.1'),
}
# Android ABI -> (clang target triple, 32-bit host needed, folder of vendor/joltPhysics/native or None)
ABIS = {
    'arm64-v8a': ('aarch64-linux-android24', False, 'android-arm64'),
    'armeabi-v7a': ('armv7a-linux-androideabi24', True, 'android-arm'),
    'x86_64': ('x86_64-linux-android24', False, None),
}
LUAJIT_HEADERS = ('lua.h', 'lauxlib.h', 'lualib.h', 'luaconf.h', 'lua.hpp', 'luajit.h')


def run(command, **kwargs):
    print('+', ' '.join(str(part) for part in command))
    subprocess.run([str(part) for part in command], check=True, **kwargs)


def ndk_toolchain():
    ndk = os.environ.get('ANDROID_NDK_HOME') or os.environ.get('ANDROID_NDK_ROOT')
    if not ndk:
        sys.exit('Set ANDROID_NDK_HOME to the NDK directory (r26 or newer).')
    host = {'linux': 'linux-x86_64', 'darwin': 'darwin-x86_64', 'win32': 'windows-x86_64'}[sys.platform]
    bin_dir = pathlib.Path(ndk) / 'toolchains' / 'llvm' / 'prebuilt' / host / 'bin'
    if not bin_dir.is_dir():
        sys.exit(f'Not an NDK directory: {ndk}')
    return bin_dir


def fetch_sources():
    DEPS.mkdir(exist_ok=True)
    for name, (url, tag) in SOURCES.items():
        target = DEPS / name
        if target.exists():
            continue
        run(['git', 'clone', '--depth', '1', '--branch', tag, url, target])


def build_luajit(abi, bin_dir):
    triple, needs32, _ = ABIS[abi]
    prefix = DEPS / 'luajit' / abi
    if (prefix / 'lib' / 'libluajit-5.1.a').is_file():
        return
    source = DEPS / 'build-luajit' / abi
    shutil.rmtree(source, ignore_errors=True)
    shutil.copytree(DEPS / 'LuaJIT', source, ignore=shutil.ignore_patterns('.git'))
    suffix = '.cmd' if sys.platform == 'win32' else ''
    clang = str(bin_dir / (triple + '-clang' + suffix))
    run([
        'make', '-C', source, '-j4', 'amalg',
        'HOST_CC=gcc -m32' if needs32 else 'HOST_CC=gcc',
        'STATIC_CC=' + clang + ' -fPIC',
        'DYNAMIC_CC=' + clang + ' -fPIC',
        'TARGET_LD=' + clang,
        'TARGET_AR=' + str(bin_dir / 'llvm-ar') + ' rcus',
        'TARGET_STRIP=' + str(bin_dir / 'llvm-strip'),
        'TARGET_SYS=Linux',
    ])
    (prefix / 'lib').mkdir(parents=True, exist_ok=True)
    include = prefix / 'include' / 'luajit-2.1'
    include.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / 'src' / 'libluajit.a', prefix / 'lib' / 'libluajit-5.1.a')
    for header in LUAJIT_HEADERS:
        shutil.copy2(source / 'src' / header, include / header)
    shutil.rmtree(source, ignore_errors=True)


def build_katsa_libraries(abis):
    run([sys.executable, ROOT / 'tools' / 'native' / 'build.py', 'android'])
    for abi in abis:
        target = JNI / abi
        target.mkdir(parents=True, exist_ok=True)
        for library in (ROOT / 'build' / 'native' / 'android' / abi).glob('*.so'):
            shutil.copy2(library, target / library.name)
        jolt = ABIS[abi][2]
        if jolt:
            shutil.copy2(ROOT / 'vendor' / 'joltPhysics' / 'native' / jolt / 'libjoltc.so', target / 'libjoltc.so')
        else:
            print(f'note: no Jolt binary for {abi}; 3D physics uses the Oimo backend there')


def pack_game(game):
    sys.path.insert(0, str(ROOT / 'tools' / 'build'))
    import packageKatsa

    ASSETS.mkdir(parents=True, exist_ok=True)
    files, empty = packageKatsa.write_zip(str(ASSETS / 'game.katsa'), str(game), runtime=True)
    print(f'packed {files} files, {empty} empty folders -> {ASSETS / "game.katsa"}')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--game', type=pathlib.Path, default=ROOT, help='game folder with main.lua (default: this repository)')
    parser.add_argument('--abis', default='arm64-v8a,x86_64', help='comma separated: ' + ', '.join(ABIS))
    parser.add_argument('--skip-deps', action='store_true', help='only repack game.katsa')
    args = parser.parse_args()
    abis = [abi.strip() for abi in args.abis.split(',') if abi.strip()]
    for abi in abis:
        if abi not in ABIS:
            sys.exit(f'Unknown ABI {abi}; use {", ".join(ABIS)}')
    if not (args.game / 'main.lua').is_file():
        sys.exit(f'Game folder is missing main.lua: {args.game}')

    if not args.skip_deps:
        bin_dir = ndk_toolchain()
        fetch_sources()
        for abi in abis:
            build_luajit(abi, bin_dir)
        build_katsa_libraries(abis)
    pack_game(args.game)
    print('\nNext: cd android && gradle assembleDebug   (APK: android/app/build/outputs/apk/debug/)')


if __name__ == '__main__':
    main()
