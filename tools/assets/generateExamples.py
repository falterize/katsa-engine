"""Generate original test assets; no third-party media is required."""

import json
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sound(name, seconds, frequencies, volume):
    rate = 22050
    samples = []
    for i in range(int(rate * seconds)):
        t = i / rate
        envelope = min(1, t * 30, (seconds - t) * 20)
        value = sum(math.sin(t * f * math.tau) for f in frequencies) / len(frequencies)
        samples.append(struct.pack('<h', int(value * volume * envelope * 32767)))
    destination = ROOT / 'assets/audio' / ('ambient' if name == 'ambient.wav' else 'effects') / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(destination), 'wb') as output:
        output.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
        output.writeframes(b''.join(samples))


sound('click.wav', 0.12, [660, 990], 0.3)
sound('chime.wav', 1, [330, 495, 660], 0.3)
sound('ambient.wav', 8, [110, 165, 220], 0.08)
(ROOT / 'assets/models/examples/pyramid.obj').write_text(
    '''mtllib pyramid.mtl
o Pyramid
v -1 0 -1
v 1 0 -1
v 1 0 1
v -1 0 1
v 0 2 0
vt 0 0
vt 1 0
vt 0.5 1
usemtl Clay
f 1/1 5/3 2/2
f 2/1 5/3 3/2
f 3/1 5/3 4/2
f 4/1 5/3 1/2
f 1/1 2/2 3/3
f 1/1 3/3 4/2
'''
)
(ROOT / 'assets/models/examples/pyramid.mtl').write_text(
    'newmtl Clay\nKd 1 0.7 0.35\nmap_Kd ../../textures/surfaces/bricks.jpg\n'
)
# A rigid two-node hierarchy with indexed triangles and a quaternion animation.
positions = [-1, -1, -1, 1, -1, -1, 0, 1, 0, 0, -1, 1]
indices = [0, 2, 1, 1, 2, 3, 3, 2, 0, 0, 1, 3]
uvs = [0, 0, 1, 0, 0.5, 1, 1, 1]
times = [0, 1, 2, 3, 4]
quaternions = [
    v for t in times for v in (0, math.sin(t * math.pi / 4), 0, math.cos(t * math.pi / 4))
]
binary = bytearray()
views = []
accessors = []


def add(values, code, component_type, kind, count):
    while len(binary) % 4:
        binary.append(0)
    start = len(binary)
    binary.extend(struct.pack('<' + code * len(values), *values))
    views.append({'buffer': 0, 'byteOffset': start, 'byteLength': len(binary) - start})
    accessors.append(
        {
            'bufferView': len(views) - 1,
            'componentType': component_type,
            'count': count,
            'type': kind,
        }
    )
    return len(accessors) - 1


p = add(positions, 'f', 5126, 'VEC3', 4)
u = add(uvs, 'f', 5126, 'VEC2', 4)
i = add(indices, 'H', 5123, 'SCALAR', 12)
t = add(times, 'f', 5126, 'SCALAR', 5)
q = add(quaternions, 'f', 5126, 'VEC4', 5)
image_start = len(binary)
image_bytes = (ROOT / 'assets/textures/surfaces/stone.png').read_bytes()
binary.extend(image_bytes)
views.append({'buffer': 0, 'byteOffset': image_start, 'byteLength': len(image_bytes)})
document = {
    'asset': {'version': '2.0', 'generator': 'Katsa test asset generator'},
    'buffers': [{'byteLength': len(binary)}],
    'bufferViews': views,
    'accessors': accessors,
    'images': [{'bufferView': len(views) - 1, 'mimeType': 'image/png'}],
    'textures': [{'source': 0}],
    'materials': [
        {
            'doubleSided': True,
            'pbrMetallicRoughness': {
                'baseColorFactor': [0.6, 0.8, 1, 1],
                'baseColorTexture': {'index': 0},
                'metallicFactor': 0,
            },
        }
    ],
    'meshes': [
        {
            'primitives': [
                {'attributes': {'POSITION': p, 'TEXCOORD_0': u}, 'indices': i, 'material': 0}
            ]
        }
    ],
    'nodes': [
        {'name': 'Root', 'children': [1]},
        {'name': 'Spinner', 'mesh': 0, 'translation': [0, 0, 0]},
    ],
    'scenes': [{'nodes': [0]}],
    'scene': 0,
    'animations': [
        {
            'name': 'Turn',
            'samplers': [{'input': t, 'output': q, 'interpolation': 'LINEAR'}],
            'channels': [{'sampler': 0, 'target': {'node': 1, 'path': 'rotation'}}],
        }
    ],
}
js = json.dumps(document, separators=(',', ':')).encode()
js += b' ' * (-len(js) % 4)
binary += b'\0' * (-len(binary) % 4)
body = (
    struct.pack('<II', len(js), 0x4E4F534A)
    + js
    + struct.pack('<II', len(binary), 0x004E4942)
    + binary
)
(ROOT / 'assets/models/examples/animated.glb').write_bytes(
    b'glTF' + struct.pack('<II', 2, len(body) + 12) + body
)
