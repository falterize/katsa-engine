"""Package source, assets, dependencies and empty categories into a .love ZIP."""

from pathlib import Path
import argparse
import sys
import hashlib
import zipfile


# Repository bookkeeping that lives beside the project in Git but is not part of the game.
REPOSITORY_ONLY = {'.git', '.gitignore', 'releases'}


def is_repository_file(relative: Path) -> bool:
    return relative.parts[0] in REPOSITORY_ONLY


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
        and not is_repository_file(path.relative_to(source))
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
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('dist'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    # A fresh Git checkout has no empty scene categories; the archive must keep them.
    import restoreEmptyDirs

    restoreEmptyDirs.restore(root)
    package(root, args.output / 'Katsa-v108.2.love')


if __name__ == '__main__':
    main()
