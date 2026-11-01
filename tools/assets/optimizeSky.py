"""Remove only provably unused alpha; preserve PNG ancillary chunks and source.

Pillow is required only to regenerate this lossless asset, not to run/package.
"""

from pathlib import Path
from io import BytesIO
from PIL import Image

root = Path(__file__).resolve().parents[2]
source = root / 'assets/sources/textures/sky/dayCross-original.png'
output = root / 'assets/textures/sky/dayCross.png'
if not source.exists():
    source.parent.mkdir(parents=True, exist_ok=True)
    source.write_bytes(output.read_bytes())
raw = source.read_bytes()
image = Image.open(BytesIO(raw))
assert image.mode == 'RGBA' and image.getchannel('A').getextrema() == (255, 255)
chunks = []
offset = 8
while offset < len(raw):
    size = int.from_bytes(raw[offset : offset + 4], 'big')
    kind = raw[offset + 4 : offset + 8]
    assert kind not in (b'sBIT', b'tRNS'), 'This source needs color-dependent metadata conversion'
    assert kind not in (b'acTL', b'fcTL', b'fdAT'), 'Animated sources require separate handling'
    if kind not in (b'IHDR', b'IDAT', b'IEND'):
        chunks.append(raw[offset : offset + size + 12])
    offset += size + 12
stream = BytesIO()
image.convert('RGB').save(stream, format='PNG', compress_level=9)
encoded = stream.getvalue()
assert encoded[12:16] == b'IHDR'
output.write_bytes(encoded[:33] + b''.join(chunks) + encoded[33:])
assert Image.open(output).convert('RGBA').tobytes() == image.tobytes()
print(output, len(raw), '->', output.stat().st_size, 'identical RGBA pixels')
