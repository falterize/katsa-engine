#!/usr/bin/env python3
"""Builds the cimgui shared library for the current platform into native/<os>-<arch>/.

Linux:   g++ (libstdc++ and libgcc are linked statically; only libc and libm remain).
Windows: run from an MSYS2 MinGW-w64 shell (g++ on PATH); produces native/win-x64/cimgui.dll.
Android: build with the NDK (see docs/guides/development/imgui.md); this script prints the
         command for the ABI named in --android-abi when ANDROID_NDK_HOME is set.
The sources in vendor/cimgui are compiled as they are; nothing outside this plugin is touched.
"""
import argparse
import os
import pathlib
import platform
import subprocess
import sys

PLUGIN = pathlib.Path(__file__).resolve().parent.parent
CIMGUI = PLUGIN / 'vendor' / 'cimgui'
SOURCES = ['cimgui.cpp'] + [
    f'imgui/{name}.cpp'
    for name in ('imgui', 'imgui_draw', 'imgui_tables', 'imgui_widgets', 'imgui_demo')
]
FLAGS = ['-O2', '-fno-exceptions', '-fno-rtti', '-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS']


def host():
    name = platform.system()
    # An MSYS2/MinGW shell reports 'MINGW64_NT-10.0-...' (Cygwin 'CYGWIN_NT-...'): that is Windows.
    if name.startswith(('MINGW', 'MSYS', 'CYGWIN')):
        name = 'Windows'
    system = {'Linux': 'linux', 'Windows': 'win', 'Darwin': 'osx'}[name]
    machine = platform.machine().lower()
    arch = {'x86_64': 'x64', 'amd64': 'x64', 'aarch64': 'arm64', 'arm64': 'arm64'}.get(machine, machine)
    return system, arch


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--android-abi', help='arm64-v8a, armeabi-v7a, x86_64')
    options = parser.parse_args()
    system, arch = host()
    sources = [str(CIMGUI / name) for name in SOURCES]
    if options.android_abi:
        ndk = os.environ.get('ANDROID_NDK_HOME')
        if not ndk:
            sys.exit('Set ANDROID_NDK_HOME to the NDK folder.')
        triples = {'arm64-v8a': 'aarch64-linux-android24', 'armeabi-v7a': 'armv7a-linux-androideabi24',
                   'x86_64': 'x86_64-linux-android24'}
        compiler = f'{ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/{triples[options.android_abi]}-clang++'
        # native/android-<arch> uses the engine's names: arm64, arm, x64 (the ABI folder in the APK).
        arch = {'arm64-v8a': 'arm64', 'armeabi-v7a': 'arm', 'x86_64': 'x64'}[options.android_abi]
        output = PLUGIN / 'native' / f'android-{arch}' / 'libcimgui.so'
        command = [compiler, *FLAGS, '-fPIC', '-shared', '-static-libstdc++', f'-I{CIMGUI / "imgui"}', *sources, '-o', str(output)]
    elif system == 'win':
        output = PLUGIN / 'native' / f'win-{arch}' / 'cimgui.dll'
        command = ['g++', *FLAGS, '-shared', '-static', f'-I{CIMGUI / "imgui"}', *sources, '-o', str(output)]
    else:
        output = PLUGIN / 'native' / f'{system}-{arch}' / ('libcimgui.dylib' if system == 'osx' else 'libcimgui.so')
        command = ['g++', *FLAGS, '-fPIC', '-shared', '-static-libstdc++', '-static-libgcc', f'-I{CIMGUI / "imgui"}', *sources, '-o', str(output)]
    output.parent.mkdir(parents=True, exist_ok=True)
    print(' '.join(command))
    subprocess.run(command, check=True, cwd=CIMGUI)
    print(f'built {output} ({output.stat().st_size} bytes)')


if __name__ == '__main__':
    main()
