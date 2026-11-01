"""Build or verify the project-owned Jolt worker/contact bridge (Zig 0.13.0)."""

from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
bridge = root / 'source/engine/physics/3d/backends/jolt/native'
manifest_path = bridge / 'manifest.json'
source = bridge / 'bridge.c'
header = root / 'vendor/joltPhysics/include/joltc.h'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiler', default='zig')
parser.add_argument('--target', choices=('win-x64', 'linux-x64', 'all'), default='win-x64')
parser.add_argument('--verify', action='store_true')
args = parser.parse_args()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


if args.verify:
    manifest = json.loads(manifest_path.read_text())
    assert digest(source) == manifest['sourceSha256'], 'Bridge source differs from compiled source'
    assert (
        digest(header) == manifest['headerSha256']
    ), 'Pinned joltc header differs from build input'
    for platform, entry in manifest['binaries'].items():
        path = bridge / platform / entry['filename']
        assert path.stat().st_size == entry['bytes'] and digest(path) == entry['sha256'], platform
        print('VERIFIED', platform, entry['sha256'])
else:
    compiler = str(Path(shutil.which(args.compiler) or args.compiler).resolve())
    version = subprocess.check_output([compiler, 'version'], text=True).strip()
    assert version == '0.13.0', 'Use the pinned Zig 0.13.0 compiler'
    platforms = {
        'win-x64': ('x86_64-windows-gnu', 'katsa_jolt.dll'),
        'linux-x64': ('x86_64-linux-gnu.2.17', 'libkatsa_jolt.so'),
    }
    selected = platforms if args.target == 'all' else {args.target: platforms[args.target]}
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {'binaries': {}}
    # Do not attest unrebuilt binaries after a source or ABI-header change.
    if manifest.get('sourceSha256') != digest(source) or manifest.get('headerSha256') != digest(
        header
    ):
        manifest['binaries'] = {}
    manifest.update(
        abi=1, compiler='Zig ' + version, sourceSha256=digest(source), headerSha256=digest(header)
    )
    for platform, (target, filename) in selected.items():
        flags = [
            '-std=gnu11',
            '-shared',
            '-O2',
            '-s',
            '-mcpu=baseline',
            '-target',
            target,
            '-Wall',
            '-Wextra',
            '-Werror',
        ]
        if platform == 'linux-x64':
            flags += ['-fPIC', '-pthread']
        with tempfile.TemporaryDirectory(prefix='katsa-jolt-') as directory:
            output = Path(directory) / filename
            subprocess.run(
                [compiler, 'cc', *flags, '-I', str(header.parent), str(source), '-o', str(output)],
                check=True,
            )
            destination = bridge / platform / filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(output, destination)
        manifest['binaries'][platform] = dict(
            filename=filename,
            target=target,
            flags=flags,
            bytes=destination.stat().st_size,
            sha256=digest(destination),
        )
        print('BUILT', platform, manifest['binaries'][platform]['sha256'])
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
