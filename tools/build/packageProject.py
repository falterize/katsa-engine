"""Package source, assets, dependencies and empty categories into a .love ZIP."""

from pathlib import Path
import argparse
import hashlib
import zipfile


def package(source: Path, target: Path):
    source = source.resolve()
    target = target.resolve()
    if not (source / 'main.lua').is_file():
        raise ValueError(f'Project is missing main.lua: {source}')
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix('.tmp')
    output_root = target.parent
    # Exclude a nested output directory, but allow building into the source root.
    output_is_child = output_root != source and output_root.is_relative_to(source)
    entries = sorted(
        path
        for path in source.rglob('*')
        if (path.is_file() or path.is_dir())
        and '__pycache__' not in path.relative_to(source).parts
        and path not in {target, temporary}
        and not (output_is_child and path.is_relative_to(output_root))
    )
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in entries:
                # Directory entries retain empty scene categories without marker files.
                archive.write(path, path.relative_to(source).as_posix())
        with zipfile.ZipFile(temporary) as archive:
            assert archive.testzip() is None
            assert 'main.lua' in archive.namelist()
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    print(target, hashlib.sha256(target.read_bytes()).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('dist'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    package(root, args.output / 'Katsa-v108.love')


if __name__ == '__main__':
    main()
