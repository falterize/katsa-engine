#!/usr/bin/env python3
"""Builds Katsa's native libraries for one target.

    python tools/native/build.py <target> [library ...]

Targets:
    linux     needs clang or gcc
    windows   needs llvm-mingw (x86_64-w64-mingw32-clang) or mingw-w64 gcc on PATH
    android   needs ANDROID_NDK_HOME; builds arm64-v8a, armeabi-v7a and x86_64
    macos     run on a Mac; universal x86_64 + arm64 dylibs

Libraries (all of them when none is named):
    katsa_native   UTF-8 files, image/audio/font decoding (native/src/native/*.c)
    katsa_box2d    Box2D bridge (native/src/box2d/*.cpp + vendor/box2d)
    katsa_net      ENet bridge (katsa_net.c + vendor/enet)
    katsa_threads  OS threads, channels and shared arrays for actors (katsa_threads.c)
    host           the katsa executable (native/src/host/*.c); built only when named or when
                   LUAJIT_PREFIX (linux, macos) / LUAJIT_WIN_LIB (windows) is set

A library may be named as `katsa_net`, `net`, `katsa_net.c` or `--katsa_net.c`; a file of
katsa_native (`font.c`, `image`, ...) selects katsa_native. Examples:

    python tools/native/build.py windows                      # everything
    python tools/native/build.py windows katsa_net threads    # only these two DLLs

Output goes to build/native/<target>/ (android: build/native/android/<abi>/).
See docs/guides/katsa/building.md.
"""
import os
import pathlib
import platform
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / 'native' / 'src'
VENDOR = ROOT / 'vendor'
LUAJIT = os.environ.get('LUAJIT_PREFIX', '/usr/local')

# Source lists and flags per library -------------------------------------------------------------

NATIVE_SOURCES = sorted((SRC / 'native').glob('*.c'))
NATIVE_FLAGS = ['-O2', '-fvisibility=hidden', '-I' + str(VENDOR / 'stb'), '-I' + str(SRC)]

BOX2D_SOURCES = sorted((VENDOR / 'box2d' / 'Box2D').rglob('*.cpp')) + sorted((SRC / 'box2d').glob('*.cpp'))
BOX2D_FLAGS = ['-O2', '-DNDEBUG', '-fvisibility=hidden', '-I' + str(VENDOR / 'box2d'), '-std=c++11']

ENET = VENDOR / 'enet'
NET_SOURCES = [
    ENET / name
    for name in ('callbacks.c', 'compress.c', 'host.c', 'list.c', 'packet.c', 'peer.c', 'protocol.c')
] + [SRC / 'katsa_net.c']
NET_FLAGS = ['-O2', '-fvisibility=hidden', '-DHAS_SOCKLEN_T', '-I' + str(ENET / 'include')]

THREADS_SOURCES = [SRC / 'katsa_threads.c']
THREADS_FLAGS = ['-O2', '-fvisibility=hidden']

# android.c compiles to nothing off Android; Android builds the host with CMake instead.
HOST_SOURCES = sorted((SRC / 'host').glob('*.c'))

LIBRARIES = ['katsa_native', 'katsa_box2d', 'katsa_net', 'katsa_threads', 'host']


# Helpers ----------------------------------------------------------------------------------------

def run(command):
    command = [str(part) for part in command]
    print(' '.join(command))
    subprocess.run(command, check=True)


def compiler(*names):
    for name in names:
        path = shutil.which(name)
        if path:
            return path
    sys.exit('No compiler found; tried: ' + ', '.join(names))


class Toolchain:
    """How one target compiles and names a shared library.

    cc / cxx    C and C++ compilers
    shared      flags that make a shared library
    prefix      file name prefix ('lib' everywhere except Windows)
    extension   '.so', '.dll' or '.dylib'
    static      link flags that bundle the compiler runtime into the library
    cxx_static  the same for C++ libraries
    """

    def __init__(self, cc, cxx, shared, prefix, extension, static, cxx_static):
        self.cc, self.cxx = cc, cxx
        self.shared = shared
        self.prefix, self.extension = prefix, extension
        self.static, self.cxx_static = static, cxx_static

    def library(self, out, name):
        return out / (self.prefix + name + self.extension)


def linux_toolchain():
    return Toolchain(
        compiler('clang', 'gcc', 'cc'),
        lambda: compiler('clang++', 'g++', 'c++'),
        ['-shared', '-fPIC'], 'lib', '.so', [], ['-static-libstdc++'],
    )


def windows_toolchain():
    return Toolchain(
        compiler('x86_64-w64-mingw32-clang', 'x86_64-w64-mingw32-gcc'),
        lambda: compiler('x86_64-w64-mingw32-clang++', 'x86_64-w64-mingw32-g++'),
        ['-shared'], '', '.dll', ['-static'], ['-static'],
    )


def macos_toolchain():
    # Oldest macOS the libraries should run on; override with MACOSX_DEPLOYMENT_TARGET.
    os.environ.setdefault('MACOSX_DEPLOYMENT_TARGET', '10.13')
    universal = ['-dynamiclib', '-arch', 'x86_64', '-arch', 'arm64']
    return Toolchain(
        compiler('clang'), lambda: compiler('clang++'), universal, 'lib', '.dylib', [], [],
    )


# One function per library; each takes the toolchain, the output folder and the target name. ----

def build_native(tc, out, target):
    libs = [] if target == 'windows' else ['-lm']
    run([tc.cc, *tc.shared, *NATIVE_FLAGS, *NATIVE_SOURCES, *libs, *tc.static,
         '-o', tc.library(out, 'katsa_native')])


def build_box2d(tc, out, target):
    run([tc.cxx(), *tc.shared, *BOX2D_FLAGS, *BOX2D_SOURCES, *tc.cxx_static,
         '-o', tc.library(out, 'katsa_box2d')])


def build_net(tc, out, target):
    if target == 'windows':
        platform_source, libs = ENET / 'win32.c', ['-static', '-lws2_32', '-lwinmm']
    else:
        platform_source, libs = ENET / 'unix.c', []
    run([tc.cc, *tc.shared, *NET_FLAGS, *NET_SOURCES, platform_source, *libs,
         '-o', tc.library(out, 'katsa_net')])


def build_threads(tc, out, target):
    libs = {'linux': ['-lpthread'], 'windows': ['-static']}.get(target, [])
    run([tc.cc, *tc.shared, *THREADS_FLAGS, *THREADS_SOURCES, *libs,
         '-o', tc.library(out, 'katsa_threads')])


def build_host(tc, out, target, required):
    """The executable links LuaJIT statically and exports its C API for katsa_threads."""
    if target == 'windows':
        lib = os.environ.get('LUAJIT_WIN_LIB')
        if not lib:
            if required:
                sys.exit('Set LUAJIT_WIN_LIB to a Windows libluajit-5.1.a '
                         '(see docs/guides/katsa/building.md)')
            return
        include = os.environ.get('LUAJIT_WIN_INCLUDE', LUAJIT + '/include/luajit-2.1')
        subsystem = '-mwindows' if os.environ.get('KATSA_GUI') else '-mconsole'
        run([tc.cc, '-O2', '-I' + include, *HOST_SOURCES, lib, '-static', subsystem,
             '-o', out / 'katsa.exe'])
        return
    if not os.environ.get('LUAJIT_PREFIX'):
        if required:
            sys.exit('Set LUAJIT_PREFIX to the LuaJIT install that has lib/libluajit-5.1.a')
        return
    flags = ['-O2', '-rdynamic']
    if target == 'macos':
        # LuaJIT on x86_64 macOS needs the low 4 GB free, so the executable is linked with a small
        # page zero at a high image base. arm64 needs neither flag. The host is built for the Mac
        # that runs the script (a static libluajit-5.1.a is single-architecture).
        arch = 'arm64' if platform.machine() in ('arm64', 'aarch64') else 'x86_64'
        flags = ['-arch', arch, '-O2', '-Wl,-export_dynamic']
        if arch == 'x86_64':
            flags += ['-Wl,-pagezero_size,10000', '-Wl,-image_base,100000000']
    run([tc.cc, *flags, '-I' + LUAJIT + '/include/luajit-2.1', *HOST_SOURCES,
         LUAJIT + '/lib/libluajit-5.1.a', '-lm', '-ldl', '-o', out / 'katsa'])


BUILDERS = {
    'katsa_native': build_native,
    'katsa_box2d': build_box2d,
    'katsa_net': build_net,
    'katsa_threads': build_threads,
}


# Targets ----------------------------------------------------------------------------------------

def build_desktop(toolchain, out, target, names, host_named):
    for name in names:
        if name == 'host':
            build_host(toolchain, out, target, host_named)
        else:
            BUILDERS[name](toolchain, out, target)


def build_android(out, names):
    ndk = os.environ.get('ANDROID_NDK_HOME') or os.environ.get('ANDROID_NDK_ROOT')
    if not ndk:
        sys.exit('Set ANDROID_NDK_HOME to your NDK directory')
    host = {'linux': 'linux-x86_64', 'darwin': 'darwin-x86_64', 'win32': 'windows-x86_64'}[sys.platform]
    bin_dir = pathlib.Path(ndk) / 'toolchains' / 'llvm' / 'prebuilt' / host / 'bin'
    suffix = '.cmd' if sys.platform == 'win32' else ''
    abis = {
        'arm64-v8a': 'aarch64-linux-android24',
        'armeabi-v7a': 'armv7a-linux-androideabi24',
        'x86_64': 'x86_64-linux-android24',
    }
    for abi, triple in abis.items():
        target_dir = out / abi
        target_dir.mkdir(parents=True, exist_ok=True)
        cc = bin_dir / (triple + '-clang' + suffix)
        cxx = bin_dir / (triple + '-clang++' + suffix)
        toolchain = Toolchain(cc, lambda cxx=cxx: cxx, ['-shared', '-fPIC'], 'lib', '.so', [],
                              ['-static-libstdc++'])
        for name in names:
            if name != 'host':  # Android runs the engine from its own activity, not this host.
                BUILDERS[name](toolchain, target_dir, 'android')


TOOLCHAINS = {'linux': linux_toolchain, 'windows': windows_toolchain, 'macos': macos_toolchain}
TARGETS = ['linux', 'windows', 'macos', 'android']


# Source file names (without extension) that select the library they belong to, so
# `build.py windows font.c` builds katsa_native. File names shared by several libraries are
# left out on purpose.
FILE_LIBRARIES = {
    'katsa_native': ('native', 'core', 'filesystem', 'image', 'audio', 'font'),
    'katsa_box2d': ('box2d', 'bridge', 'world', 'body', 'shape', 'fixture', 'contact', 'joint'),
}


def library_name(argument):
    """'--katsa_net.c', 'katsa_net.c', 'katsa_net', 'net' and file names such as 'font.c'."""
    name = argument.lstrip('-')
    for ending in ('.cpp', '.c', '.h'):
        if name.endswith(ending):
            name = name[: -len(ending)]
    for library, files in FILE_LIBRARIES.items():
        if name in files:
            return library
    if not name.startswith('katsa_') and name != 'host':
        name = 'katsa_' + name
    if name not in LIBRARIES:
        sys.exit('Unknown library: ' + argument + '\nKnown: ' + ', '.join(LIBRARIES))
    return name


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in TARGETS:
        sys.exit(__doc__)
    target = sys.argv[1]
    requested = [library_name(argument) for argument in sys.argv[2:]]
    names = [name for name in LIBRARIES if not requested or name in requested]
    out = ROOT / 'build' / 'native' / target
    out.mkdir(parents=True, exist_ok=True)
    if target == 'android':
        build_android(out, names)
    else:
        build_desktop(TOOLCHAINS[target](), out, target, names, 'host' in requested)
    print('Built ' + ', '.join(names) + ' into', out)


if __name__ == '__main__':
    main()
