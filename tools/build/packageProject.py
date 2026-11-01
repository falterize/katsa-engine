"""Package the project (source, assets, dependencies, empty scene categories) into a .katsa archive.

    python tools/build/packageProject.py --output dist
    python tools/build/packageProject.py --output dist --host build/host/linux/katsa   (fused exe)

The archive is named after source/engine/core/version.lua. Run it with `katsa Katsa-<version>.katsa`.
See docs/guides/katsa/building.md for every target platform.
"""

from pathlib import Path
import argparse
import hashlib
import re
import stat
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import packageKatsa  # noqa: E402
import restoreEmptyDirs  # noqa: E402


def project_version(root: Path) -> str:
    text = (root / 'source' / 'engine' / 'core' / 'version.lua').read_text(encoding='utf-8')
    match = re.search(r"value\s*=\s*'([^']+)'", text)
    if not match:
        raise ValueError('Cannot read the version from source/engine/core/version.lua')
    return match.group(1)


def package(root: Path, target: Path, host: Path | None = None) -> Path:
    if not (root / 'main.lua').is_file():
        raise ValueError(f'Project is missing main.lua: {root}')
    target.parent.mkdir(parents=True, exist_ok=True)
    if host is None:
        files, directories = packageKatsa.write_zip(str(target), str(root))
    else:
        temporary = target.with_suffix('.zip.tmp')
        try:
            files, directories = packageKatsa.write_zip(str(temporary), str(root), runtime=True)
            target.write_bytes(host.read_bytes() + temporary.read_bytes())
        finally:
            temporary.unlink(missing_ok=True)
        target.chmod(target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f'packed {files} files, {directories} empty folders -> {target}')
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('dist'))
    parser.add_argument('--host', type=Path, help='katsa host executable to fuse with')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    # A fresh Git checkout has no empty scene categories; the archive must keep them.
    restoreEmptyDirs.restore(root)
    name = f'Katsa-{project_version(root)}'
    target = args.output / (name if args.host else name + '.katsa')
    result = package(root, target, args.host)
    print(hashlib.sha256(result.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
