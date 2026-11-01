"""Recreate the empty scene category directories that Git cannot store.

The project forbids marker files, so the list of intentionally empty directories lives in
tools/project/emptyDirectories.txt. Run this after cloning and before packaging or auditing.
Use --update after adding or removing an empty category to rewrite the list from the tree.
"""

from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'tools/project/emptyDirectories.txt'


def restore(root: Path = ROOT, manifest: Path = MANIFEST) -> int:
    created = 0
    for line in manifest.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line:
            continue
        target = root / line
        if not target.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            created += 1
    return created


def update(root: Path = ROOT, manifest: Path = MANIFEST) -> int:
    empty = sorted(
        path.relative_to(root).as_posix()
        for path in root.rglob('*')
        if path.is_dir()
        and '.git' not in path.relative_to(root).parts
        and '__pycache__' not in path.relative_to(root).parts
        and not any(path.iterdir())
    )
    manifest.write_text('\n'.join(empty) + '\n', encoding='utf-8')
    return len(empty)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--update', action='store_true', help='rewrite the list from the tree')
    args = parser.parse_args()
    if args.update:
        print(f'{update()} empty directories recorded in {MANIFEST.relative_to(ROOT)}')
    else:
        print(f'{restore()} empty directories created')


if __name__ == '__main__':
    main()
