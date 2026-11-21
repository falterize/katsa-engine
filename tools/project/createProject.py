"""Create an independent game with the engine, one scene and no demonstration browser."""

from pathlib import Path
import argparse
import re
import shutil
import tempfile


def create(source: Path, target: Path, name: str, identity: str | None = None,
           examples: Path | None = None):
    if not re.fullmatch(r'[a-z][a-z0-9-]{0,59}', name):
        raise ValueError('Use a lowercase game name containing letters, digits and hyphens')
    identity = identity or 'katsa-' + name
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', identity):
        raise ValueError('Use a stable save identity with letters, digits, underscores or hyphens')
    source, target = source.resolve(), target.resolve()
    # The starter scene lives in the examples project (a sibling checkout by default).
    examples = (examples or source.parent / 'katsa-engine-examples').resolve()
    starter = examples / 'game/scenes/starterGame'
    if not starter.is_dir():
        raise FileNotFoundError(f'Starter scene not found, pass --examples <folder>: {starter}')
    if target.exists():
        raise FileExistsError(f'Destination already exists: {target}')
    if target.is_relative_to(source):
        raise ValueError('Create the game outside the engine source folder')
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='katsa-create-', dir=target.parent) as temporary:
        stage = Path(temporary) / 'game'
        shutil.copytree(source / 'tools/project/templates/game', stage)
        scene = stage / 'game/scenes/start'
        shutil.copytree(starter, scene)
        scene_settings = scene / 'menu-settings.lua'
        scene_settings.write_text(
            scene_settings.read_text(encoding='utf-8').replace(
                "id = 'starterGame'", "id = 'start'"
            ).replace("title = 'Starter Game'", "title = 'Start'"),
            encoding='utf-8', newline='\n',
        )
        for directory in (
            'source/engine', 'source/runtime', 'vendor', 'assets/shaders',
            'assets/textures/engine', 'assets/fonts/engine', 'tools/run',
            'tools/build',
        ):
            shutil.copytree(source / directory, stage / directory,
                            ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        for name_on_disk in ('LICENSE', 'stylua.toml', '.styluaignore', '.editorconfig'):
            shutil.copy2(source / name_on_disk, stage / name_on_disk)
        (stage / 'docs').mkdir(exist_ok=True)
        shutil.copy2(source / 'docs/AGENTS.md', stage / 'docs/AGENTS.md')
        for category in ('models', 'textures', 'audio', 'shaders', 'fonts'):
            (stage / 'assets' / category).mkdir(exist_ok=True)
        project = stage / 'conf.lua'
        settings = project.read_text(encoding='utf-8')
        settings = settings.replace("'My Game'", repr(name.replace('-', ' ').title()))
        settings = settings.replace("'katsa-my-game'", repr(identity))
        project.write_text(settings, encoding='utf-8', newline='\n')
        stage.rename(target)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--name', required=True)
    parser.add_argument('--identity', help='Stable application save identity, reused across game updates')
    parser.add_argument('--examples', type=Path, help='The katsa-engine-examples folder (default: next to the engine)')
    args = parser.parse_args()
    print(create(Path(__file__).resolve().parents[2], args.destination, args.name, args.identity,
                 args.examples))


if __name__ == '__main__':
    main()
