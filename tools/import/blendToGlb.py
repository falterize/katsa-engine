#!/usr/bin/env python3
"""Converts .blend files to the GLB the Katsa runtime imports, using an installed Blender.

    python tools/import/blendToGlb.py model.blend              # writes model.blend.glb next to it
    python tools/import/blendToGlb.py model.blend out/model.glb

`model.blend.glb` beside a .blend is what the runtime (and `packageKatsa.py --convert-blend`) look for,
so a game shipped with these files needs no Blender. Blender is found through KATSA_BLENDER / BLENDER,
PATH, or its usual install folders.
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPORT_SCRIPT = ROOT / 'source' / 'engine' / 'import' / 'blendExport.py'


def find_blender():
    for name in ('KATSA_BLENDER', 'BLENDER'):
        value = os.environ.get(name)
        if value:
            if Path(value).is_file():
                return value
            sys.exit(f'{name} points to a missing file: {value}')
    found = shutil.which('blender')
    if found:
        return found
    candidates = sorted(glob.glob(r'C:\Program Files\Blender Foundation\Blender *\blender.exe'), reverse=True)
    candidates += ['/Applications/Blender.app/Contents/MacOS/Blender', '/snap/bin/blender']
    for candidate in candidates:
        if Path(candidate).is_file():
            return candidate
    sys.exit('Blender was not found. Install Blender 3.6+ or set KATSA_BLENDER to its executable.')


def convert(blend: Path, output: Path) -> Path:
    blender = find_blender()
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [blender, '--background', '--factory-startup', '--python-exit-code', '1', str(blend),
         '--python', str(EXPORT_SCRIPT), '--', str(output)],
        check=True,
    )
    if not output.is_file():
        sys.exit(f'Blender finished but wrote no file: {output}')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('blend', type=Path)
    parser.add_argument('output', type=Path, nargs='?')
    args = parser.parse_args()
    output = args.output or args.blend.with_name(args.blend.name + '.glb')
    print(convert(args.blend.resolve(), output.resolve()))


if __name__ == '__main__':
    main()
