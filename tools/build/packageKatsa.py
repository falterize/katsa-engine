#!/usr/bin/env python3
"""Builds .katsa game archives and fused executables.

    # Game archive (run with `katsa Game.katsa`)
    python tools/build/packageKatsa.py --source <game folder> --output dist/Game.katsa

    # Generic runtime: a host with only the Lua runtime appended (run with `katsa Game.katsa`)
    python tools/build/packageKatsa.py --runtime-only --host native/build/windows/katsa.exe --output dist/katsa.exe

    # Game and runtime in one file
    python tools/build/packageKatsa.py --source <game folder> --host native/build/linux/katsa --output dist/Game

    # .blend files converted to <name>.blend.glb with Blender (the originals are left out)
    python tools/build/packageKatsa.py --source <game folder> --convert-blend --output dist/Game.katsa

    # Plain archive that carries the runtime too (what the Android APK stores as assets/game.katsa)
    python tools/build/packageKatsa.py --source <game folder> --with-runtime --output dist/game.katsa

An archive is a plain ZIP. When a host is given, the file is `[host binary][ZIP]`; ZIP offsets stay
relative to the archive start, which is how the C host and the Lua reader find the entries.
The runtime part (`source/katsa/**` and `__katsa/boot.lua`, taken from this repository) is stored
without compression because the C host reads only STORE entries; everything else is deflated.
`validation/` is omitted unless --with-validation is given. Empty folders are kept as directory entries.
"""

from pathlib import Path
import argparse
import hashlib
import stat
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BOOT_SOURCE = ROOT / 'source' / 'katsa' / 'host' / 'entry.lua'
RUNTIME_DIR = ROOT / 'source' / 'katsa'

# Top-level names that are never part of a game archive.
SKIPPED_TOP = {'.git', '.github', 'android', 'build', 'dist', 'native', 'tools', 'docs', '__pycache__', 'lib'}
# Third-party C/C++ sources are only needed to build the native libraries.
SKIPPED_VENDOR = {'box2d', 'enet', 'stb'}
SKIPPED_NAMES = {'__pycache__', '.DS_Store', 'Thumbs.db'}
SKIPPED_SUFFIXES = {'.pyc'}
FIXED_TIME = (2020, 1, 1, 0, 0, 0)


def _skipped(relative: Path, with_validation: bool, is_project: bool) -> bool:
    parts = relative.parts
    if any(part in SKIPPED_NAMES for part in parts) or relative.suffix in SKIPPED_SUFFIXES:
        return True
    if not is_project:
        return False
    if parts[0] in SKIPPED_TOP or parts[0].startswith('.'):
        return True
    if parts[0] == 'validation' and not with_validation:
        return True
    return len(parts) > 1 and parts[0] == 'vendor' and parts[1] in SKIPPED_VENDOR


def _info(name: str, directory: bool, stored: bool) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name + '/' if directory else name, FIXED_TIME)
    info.compress_type = zipfile.ZIP_STORED if stored or directory else zipfile.ZIP_DEFLATED
    info.external_attr = (0o40755 if directory else 0o100644) << 16
    return info


def _blend_to_glb(path: Path) -> bytes:
    import tempfile

    sys.path.insert(0, str(ROOT / 'tools' / 'import'))
    import blendToGlb

    with tempfile.TemporaryDirectory() as folder:
        return blendToGlb.convert(path, Path(folder) / 'model.glb').read_bytes()


def write_zip(
    target: str,
    source: str | None,
    runtime: bool = False,
    with_validation: bool = False,
    runtime_only: bool = False,
    convert_blend: bool = False,
):
    """Writes the archive and returns (file count, empty-directory count).

    `source` is the game folder (None with runtime_only). With `runtime` the Lua runtime from this
    repository is added; when the game folder already contains it, the copy is stored uncompressed.
    """
    entries: dict[str, tuple[Path, bool]] = {}
    directories: set[str] = set()
    if source is not None and not runtime_only:
        base = Path(source).resolve()
        is_project = base == ROOT
        for path in sorted(base.rglob('*')):
            relative = path.relative_to(base)
            if _skipped(relative, with_validation, is_project):
                continue
            name = relative.as_posix()
            if path.is_dir():
                directories.add(name)
            else:
                entries[name] = (path, False)
    if runtime or runtime_only:
        for path in sorted(RUNTIME_DIR.rglob('*')):
            relative = path.relative_to(ROOT)
            if _skipped(relative, with_validation, False):
                continue
            if path.is_file():
                entries[relative.as_posix()] = (path, True)
        entries['__katsa/boot.lua'] = (BOOT_SOURCE, True)

    # A directory entry is only needed for folders without files (the reader derives the rest).
    occupied = set()
    for name in entries:
        parts = name.split('/')
        for i in range(1, len(parts)):
            occupied.add('/'.join(parts[:i]))
    empty = sorted(name for name in directories if name not in occupied)

    out = Path(target)
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(entries):
            path, stored = entries[name]
            if convert_blend and name.lower().endswith('.blend'):
                # The runtime prefers `<file>.blend.glb`, so shipped games need no Blender.
                archive.writestr(_info(name + '.glb', False, False), _blend_to_glb(path))
                continue
            archive.writestr(_info(name, False, stored), path.read_bytes())
        for name in empty:
            archive.writestr(_info(name, True, True), b'')
    return len(entries), len(empty)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', type=Path, help='game folder (must contain main.lua)')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--host', type=Path, help='katsa host executable to put in front of the archive')
    parser.add_argument('--runtime-only', action='store_true', help='pack only the Lua runtime (generic katsa executable)')
    parser.add_argument('--with-runtime', action='store_true', help='add the Lua runtime to a plain archive (no host)')
    parser.add_argument('--convert-blend', action='store_true', help='convert .blend files to .blend.glb (needs Blender)')
    parser.add_argument('--with-validation', action='store_true')
    args = parser.parse_args()
    if not args.runtime_only and args.source is None:
        sys.exit('Give --source <game folder> or --runtime-only')
    if args.runtime_only and not args.host:
        sys.exit('--runtime-only needs --host (a plain .katsa archive would be empty)')
    if args.source is not None and not (args.source / 'main.lua').is_file():
        sys.exit(f'Game folder is missing main.lua: {args.source}')

    fused = args.host is not None
    archive_path = args.output.with_name(args.output.name + '.zip.tmp') if fused else args.output
    try:
        files, empty = write_zip(
            str(archive_path),
            str(args.source) if args.source else None,
            runtime=fused or args.with_runtime,
            with_validation=args.with_validation,
            runtime_only=args.runtime_only,
            convert_blend=args.convert_blend,
        )
        if fused:
            args.output.write_bytes(args.host.read_bytes() + archive_path.read_bytes())
            args.output.chmod(args.output.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    finally:
        if fused:
            archive_path.unlink(missing_ok=True)
    print(f'packed {files} files, {empty} empty folders -> {args.output}')
    print(hashlib.sha256(args.output.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
