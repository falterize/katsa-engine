#!/usr/bin/env python3
"""Builds the katsa_native shared library for one target.

    python tools/native/build.py linux            # needs clang or gcc
    python tools/native/build.py windows          # needs llvm-mingw (x86_64-w64-mingw32-clang) on PATH
    python tools/native/build.py android          # needs ANDROID_NDK_HOME; builds arm64-v8a, armeabi-v7a, x86_64
    python tools/native/build.py macos            # run on a Mac; builds a universal x86_64 + arm64 dylib

Output goes to build/native/<target>/. See docs/guides/katsa/building.md.
"""
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / 'native' / 'src'
VENDOR = ROOT / 'vendor'
SOURCES = [SRC / 'katsa_native.c', SRC / 'katsa_vorbis_impl.c', SRC / 'katsa_font_impl.c']
FLAGS = ['-O2', '-fvisibility=hidden', '-I' + str(VENDOR / 'stb'), '-I' + str(SRC)]


def run(command):
    print(' '.join(str(part) for part in command))
    subprocess.run([str(part) for part in command], check=True)


def compiler(*names):
    for name in names:
        path = shutil.which(name)
        if path:
            return path
    sys.exit('No compiler found; tried: ' + ', '.join(names))


HOST = SRC / 'katsa_host.c'
BOX2D_DIR = VENDOR / 'box2d' / 'Box2D'
BOX2D_SOURCES = sorted(BOX2D_DIR.rglob('*.cpp')) + [SRC / 'katsa_box2d.cpp']
BOX2D_FLAGS = ['-O2', '-DNDEBUG', '-fvisibility=hidden', '-I' + str(VENDOR / 'box2d'), '-std=c++11']

LUAJIT = os.environ.get('LUAJIT_PREFIX', '/usr/local')


def build_host_linux(out):
    cc = compiler('clang', 'gcc', 'cc')
    run([cc, '-O2', '-rdynamic', '-I' + str(LUAJIT) + '/include/luajit-2.1', HOST,
         LUAJIT + '/lib/libluajit-5.1.a', '-lm', '-ldl', '-o', out / 'katsa'])


def build_host_windows(out):
    cc = compiler('x86_64-w64-mingw32-clang', 'x86_64-w64-mingw32-gcc')
    inc = os.environ.get('LUAJIT_WIN_INCLUDE', LUAJIT + '/include/luajit-2.1')
    lib = os.environ.get('LUAJIT_WIN_LIB')
    if not lib:
        sys.exit('Set LUAJIT_WIN_LIB to a Windows libluajit-5.1.a (see docs/guides/katsa/building.md)')
    run([cc, '-O2', '-I' + inc, HOST, lib, '-static', '-mwindows' if os.environ.get('KATSA_GUI') else '-mconsole', '-o', out / 'katsa.exe'])


def build_box2d_linux(out):
    cxx = compiler('clang++', 'g++', 'c++')
    run([cxx, '-shared', '-fPIC', *BOX2D_FLAGS, *BOX2D_SOURCES, '-o', out / 'libkatsa_box2d.so', '-static-libstdc++'])


def build_box2d_windows(out):
    cxx = compiler('x86_64-w64-mingw32-clang++', 'x86_64-w64-mingw32-g++')
    run([cxx, '-shared', *BOX2D_FLAGS, *BOX2D_SOURCES, '-o', out / 'katsa_box2d.dll', '-static'])


def build_box2d_macos(out):
    cxx = compiler('clang++')
    run([cxx, '-dynamiclib', '-arch', 'x86_64', '-arch', 'arm64', *BOX2D_FLAGS, *BOX2D_SOURCES, '-o', out / 'libkatsa_box2d.dylib'])


def build_linux(out):
    cc = compiler('clang', 'gcc', 'cc')
    run([cc, '-shared', '-fPIC', *FLAGS, *SOURCES, '-lm', '-o', out / 'libkatsa_native.so'])
    build_box2d_linux(out)
    if os.environ.get('LUAJIT_PREFIX'):
        build_host_linux(out)


def build_windows(out):
    cc = compiler('x86_64-w64-mingw32-clang', 'x86_64-w64-mingw32-gcc')
    run([cc, '-shared', *FLAGS, *SOURCES, '-o', out / 'katsa_native.dll', '-static'])
    build_box2d_windows(out)
    if os.environ.get('LUAJIT_WIN_LIB'):
        build_host_windows(out)


def build_macos(out):
    cc = compiler('clang')
    run([cc, '-dynamiclib', '-arch', 'x86_64', '-arch', 'arm64', *FLAGS, *SOURCES, '-lm', '-o', out / 'libkatsa_native.dylib'])
    build_box2d_macos(out)


def build_android(out):
    ndk = os.environ.get('ANDROID_NDK_HOME') or os.environ.get('ANDROID_NDK_ROOT')
    if not ndk:
        sys.exit('Set ANDROID_NDK_HOME to your NDK directory')
    host = {'linux': 'linux-x86_64', 'darwin': 'darwin-x86_64', 'win32': 'windows-x86_64'}[sys.platform]
    toolchain = pathlib.Path(ndk) / 'toolchains' / 'llvm' / 'prebuilt' / host / 'bin'
    suffix = '.cmd' if sys.platform == 'win32' else ''
    for abi, triple in {
        'arm64-v8a': 'aarch64-linux-android24',
        'armeabi-v7a': 'armv7a-linux-androideabi24',
        'x86_64': 'x86_64-linux-android24',
    }.items():
        target = out / abi
        target.mkdir(parents=True, exist_ok=True)
        run([toolchain / (triple + '-clang' + suffix), '-shared', '-fPIC', *FLAGS, *SOURCES, '-lm', '-o', target / 'libkatsa_native.so'])
        run([toolchain / (triple + '-clang++' + suffix), '-shared', '-fPIC', *BOX2D_FLAGS, *BOX2D_SOURCES, '-static-libstdc++', '-o', target / 'libkatsa_box2d.so'])


TARGETS = {'linux': build_linux, 'windows': build_windows, 'macos': build_macos, 'android': build_android}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in TARGETS:
        sys.exit(__doc__)
    out = ROOT / 'build' / 'native' / sys.argv[1]
    out.mkdir(parents=True, exist_ok=True)
    TARGETS[sys.argv[1]](out)
    print('Built into', out)


if __name__ == '__main__':
    main()
