"""Verify bundled upstream binaries; optionally restore them from pinned URLs."""

from pathlib import Path
import argparse
import hashlib
import json
import urllib.request

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--download', action='store_true')
args = parser.parse_args()
manifest = json.loads((root / 'vendor/joltPhysics/provenance.json').read_text())
for name, entry in manifest['files'].items():
    target = (root / name).resolve()
    assert target.is_relative_to(root / 'vendor/joltPhysics/native'), 'Native path escapes project'
    if args.download:
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(target.suffix + '.download')
        request = urllib.request.Request(entry['download'], headers={'User-Agent': 'Katsa'})
        with (
            urllib.request.urlopen(request, timeout=60) as response,
            temporary.open('wb') as output,
        ):
            while block := response.read(1024 * 1024):
                output.write(block)
        data = temporary.read_bytes()
        assert (
            len(data) == entry['bytes'] and hashlib.sha256(data).hexdigest() == entry['sha256']
        ), name
        temporary.replace(target)
    data = target.read_bytes()
    assert len(data) == entry['bytes'] and hashlib.sha256(data).hexdigest() == entry['sha256'], name
    print('VERIFIED', name, entry['sha256'])
