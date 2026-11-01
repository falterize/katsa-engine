"""Generate small deterministic material-map fixtures without image dependencies."""

from pathlib import Path
import struct, zlib, math

root = Path('assets/textures/materials')
root.mkdir(parents=True, exist_ok=True)


def png(name, fn):
    rows = bytearray()
    for y in range(64):
        rows.append(0)
        for x in range(64):
            rows.extend(fn(x, y))

    def chunk(t, data):
        return (
            struct.pack('>I', len(data))
            + t
            + data
            + struct.pack('>I', zlib.crc32(t + data) & 0xFFFFFFFF)
        )

    (root / name).write_bytes(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', 64, 64, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(rows))
        + chunk(b'IEND', b'')
    )


png(
    'normal.png',
    lambda x, y: (
        int(128 + 75 * math.sin(x * math.pi / 8)),
        int(128 + 45 * math.sin(y * math.pi / 8)),
        220,
    ),
)
png('roughness.png', lambda x, y: (60 if x < 32 else 230,) * 3)
png('metal.png', lambda x, y: (255 if y < 32 else 20,) * 3)
png('emission.png', lambda x, y: (255, 60, 5) if (x // 8 + y // 8) % 2 else (0, 0, 0))
