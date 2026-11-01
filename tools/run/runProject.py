"""Run a game folder or ZIP/.love/TAR/TAR.GZ/TGZ/7z project archive."""

from pathlib import Path, PurePosixPath
import argparse
import io
import shutil
import subprocess
import tarfile
import tempfile
import zipfile


def game_root(paths):
    names = set(paths)
    roots = [
        name[: -len('main.lua')]
        for name in names
        if name.endswith('main.lua') and name[: -len('main.lua')] + 'conf.lua' in names
    ]
    if '' in roots:
        return ''
    shallow = [root for root in roots if root.count('/') == 1]
    if len(shallow) != 1:
        raise ValueError('Archive must contain one game root with main.lua and conf.lua')
    return shallow[0]


def normalize(name):
    path = PurePosixPath(name.replace('\\', '/'))
    if path.is_absolute() or '..' in path.parts or ':' in name:
        raise ValueError(f'Archive entry escapes its root: {name}')
    return path.as_posix()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--love',
        default=shutil.which('love')
        or (
            'C:/Program Files/LOVE/love.exe'
            if Path('C:/Program Files/LOVE/love.exe').exists()
            else 'love'
        ),
    )
    parser.add_argument('project', type=Path)
    parser.add_argument('game_arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    source = args.project.resolve()
    if source.is_dir():
        return subprocess.call([args.love, str(source), *args.game_arguments])
    with tempfile.TemporaryDirectory(prefix='katsa-project-') as temporary:
        files = {}
        if zipfile.is_zipfile(source):
            with zipfile.ZipFile(source) as archive:
                files = {
                    normalize(info.filename): archive.read(info)
                    for info in archive.infolist()
                    if not info.is_dir()
                }
        elif tarfile.is_tarfile(source):
            with tarfile.open(source) as archive:
                for info in archive.getmembers():
                    if info.isfile():
                        files[normalize(info.name)] = archive.extractfile(info).read()
                    elif not info.isdir():
                        raise ValueError('Project TAR must contain regular files and directories')
        elif source.suffix.lower() == '.7z':
            # One conversion process handles the whole archive without extracting
            # entries to disk or spawning a process for each project file.
            converted = subprocess.check_output(
                ['tar', '--format=ustar', '-cf', '-', '@' + str(source)]
            )
            with tarfile.open(fileobj=io.BytesIO(converted)) as archive:
                for info in archive.getmembers():
                    if info.isfile():
                        files[normalize(info.name)] = archive.extractfile(info).read()
                    elif not info.isdir():
                        raise ValueError('Project 7z must contain regular files and directories')
        else:
            raise ValueError('Use a directory, ZIP/.love, TAR, TAR.GZ/TGZ or 7z archive')
        root = game_root(files)
        target = Path(temporary) / 'project.love'
        with zipfile.ZipFile(target, 'w', zipfile.ZIP_STORED) as archive:
            for name, data in files.items():
                if name.startswith(root):
                    archive.writestr(name[len(root) :], data)
        return subprocess.call([args.love, str(target), *args.game_arguments])


if __name__ == '__main__':
    raise SystemExit(main())
