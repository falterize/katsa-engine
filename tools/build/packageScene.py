"""Package one scene without copying shared engine resources into it."""

from pathlib import Path
import argparse
import subprocess
import tarfile
import zipfile


def package(source: Path, target: Path):
    source = source.resolve()
    target = target.resolve()
    for name in ('main.lua', 'settings.lua'):
        if not (source / name).is_file():
            raise ValueError(f'Scene is missing {name}: {source}')
    if target.is_relative_to(source):
        raise ValueError('Write the scene archive outside its source folder')
    target.parent.mkdir(parents=True, exist_ok=True)
    files = sorted(path for path in source.rglob('*') if path.is_file())
    directories = sorted(path for path in source.rglob('*') if path.is_dir())
    name = target.name.lower()
    temporary = target.with_name(target.name + '.tmp')
    try:
        if name.endswith(('.zip', '.love')):
            with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
                for path in directories + files:
                    archive.write(path, path.relative_to(source).as_posix())
        elif name.endswith(('.tar', '.tar.gz', '.tgz')):
            mode = 'w' if name.endswith('.tar') else 'w:gz'
            with tarfile.open(temporary, mode, format=tarfile.USTAR_FORMAT) as archive:
                for path in directories + files:
                    archive.add(path, path.relative_to(source).as_posix(), recursive=False)
        elif name.endswith('.7z'):
            # bsdtar is included with current Windows; other hosts can install it.
            subprocess.run(
                [
                    'tar',
                    '--format=7zip',
                    '-cf',
                    str(temporary),
                    '-C',
                    str(source),
                    *[p.name for p in sorted(source.iterdir())],
                ],
                check=True,
            )
        else:
            raise ValueError('Supported formats: .zip, .love, .tar, .tar.gz, .tgz, .7z')
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    print(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.source, args.output)


if __name__ == '__main__':
    main()
