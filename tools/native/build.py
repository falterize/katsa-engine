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
THIRD = ROOT / 'native' / 'third_party'
SOURCES = [SRC / 'katsa_native.c', SRC / 'katsa_vorbis_impl.c']
FLAGS = ['-O2', '-fvisibility=hidden', '-I' + str(THIRD), '-I' + str(SRC)]


def run(command):
    print(' '.join(str(part) for part in command))
    subprocess.run([str(part) for part in command], check=True)


def compiler(*names):
    for name in names:
        path = shutil.which(name)
        if path:
            return path
    sys.exit('No compiler found; tried: ' + ', '.join(names))


def build_linux(out):
    cc = compiler('clang', 'gcc', 'cc')
    run([cc, '-shared', '-fPIC', *FLAGS, *SOURCES, '-lm', '-o', out / 'libkatsa_native.so'])


def build_windows(out):
    cc = compiler('x86_64-w64-mingw32-clang', 'x86_64-w64-mingw32-gcc')
    run([cc, '-shared', *FLAGS, *SOURCES, '-o', out / 'katsa_native.dll', '-static'])


def build_macos(out):
    cc = compiler('clang')
    run([cc, '-dynamiclib', '-arch', 'x86_64', '-arch', 'arm64', *FLAGS, *SOURCES, '-lm', '-o', out / 'libkatsa_native.dylib'])


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
