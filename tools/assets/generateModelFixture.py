"""Generate a named cube and floating triangle in one core GLB file."""

from pathlib import Path
import json, struct

verts = [
    [-12, 0, -12],
    [12, 0, -12],
    [12, 24, -12],
    [-12, 24, -12],
    [-12, 0, 12],
    [12, 0, 12],
    [12, 24, 12],
    [-12, 24, 12],
]
faces = [
    (0, 2, 1),
    (0, 3, 2),
    (4, 5, 6),
    (4, 6, 7),
    (0, 1, 5),
    (0, 5, 4),
    (3, 7, 6),
    (3, 6, 2),
    (0, 4, 7),
    (0, 7, 3),
    (1, 2, 6),
    (1, 6, 5),
]
meshes = [[[*verts[i]] for f in faces for i in f], [[-16, 0, 0], [16, 0, 0], [0, 20, 0]]]
bin = bytearray()
views = []
access = []
for mesh in meshes:
    offset = len(bin)
    for v in mesh:
        bin.extend(struct.pack('<3f', *v))
    views.append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(mesh) * 12})
    access.append(
        {'bufferView': len(views) - 1, 'componentType': 5126, 'count': len(mesh), 'type': 'VEC3'}
    )
d = {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [{'nodes': [0]}],
    'nodes': [
        {'name': 'CubeTriangleAsset', 'children': [1, 2]},
        {'name': 'Cube', 'mesh': 0},
        {'name': 'FloatingTriangle', 'mesh': 1, 'translation': [0, 42, 0]},
    ],
    'meshes': [{'primitives': [{'attributes': {'POSITION': i}, 'material': i}]} for i in range(2)],
    'materials': [
        {'pbrMetallicRoughness': {'baseColorFactor': [0.2, 0.55, 1, 1]}, 'doubleSided': True},
        {'pbrMetallicRoughness': {'baseColorFactor': [1, 0.45, 0.1, 1]}, 'doubleSided': True},
    ],
    'accessors': access,
    'bufferViews': views,
    'buffers': [{'byteLength': len(bin)}],
}
js = json.dumps(d).encode()
js += b' ' * ((-len(js)) % 4)
p = Path('assets/models/examples/cubeTriangle.glb')
p.parent.mkdir(parents=True, exist_ok=True)
p.write_bytes(
    struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(bin))
    + struct.pack('<II', len(js), 0x4E4F534A)
    + js
    + struct.pack('<II', len(bin), 0x004E4942)
    + bin
)
# A small independently animated skin for deterministic import checks.
binary = bytearray()
views = []
access = []


def accessor(values, kind):
    offset = len(binary)
    for row in values:
        binary.extend(struct.pack('<' + 'f' * len(row), *row))
    views.append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(binary) - offset})
    access.append(
        {'bufferView': len(views) - 1, 'componentType': 5126, 'count': len(values), 'type': kind}
    )
    return len(access) - 1


positions = accessor(
    [[-0.2, 0, 0], [0.2, 0, 0], [0.2, 2, 0], [-0.2, 0, 0], [0.2, 2, 0], [-0.2, 2, 0]], 'VEC3'
)
weights = accessor([[1, 0, 0, 0]] * 6, 'VEC4')
joints = accessor(
    [[0, 0, 0, 0], [0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0]], 'VEC4'
)
# Joint indices must use an unsigned integer component type.
start = views[joints]['byteOffset']
raw = b''.join(
    struct.pack('<4H', *map(int, row))
    for row in [[0] * 4, [0] * 4, [1, 0, 0, 0], [0] * 4, [1, 0, 0, 0], [1, 0, 0, 0]]
)
# Keep the original 96-byte view padding so later offsets stay aligned.
binary[start : start + len(raw)] = raw
access[joints]['componentType'] = 5123
views[joints]['byteLength'] = len(raw)
identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
bind = identity.copy()
bind[13] = -1
inverse = accessor([identity, bind], 'MAT4')
times = accessor([[0], [0.5], [1]], 'SCALAR')
rotations = accessor([[0, 0, 0, 1], [0, 0, 0.70710678, 0.70710678], [0, 0, 0, 1]], 'VEC4')
d = {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [{'nodes': [0, 2]}],
    'nodes': [
        {'name': 'RootBone', 'children': [1]},
        {'name': 'TipBone', 'translation': [0, 1, 0]},
        {'name': 'Ribbon', 'mesh': 0, 'skin': 0},
    ],
    'meshes': [
        {
            'primitives': [
                {
                    'attributes': {'POSITION': positions, 'JOINTS_0': joints, 'WEIGHTS_0': weights},
                    'material': 0,
                }
            ]
        }
    ],
    'skins': [{'joints': [0, 1], 'inverseBindMatrices': inverse}],
    'materials': [
        {'pbrMetallicRoughness': {'baseColorFactor': [0.1, 1, 0.7, 1]}, 'doubleSided': True}
    ],
    'animations': [
        {
            'name': 'Bend',
            'samplers': [{'input': times, 'output': rotations, 'interpolation': 'LINEAR'}],
            'channels': [{'sampler': 0, 'target': {'node': 1, 'path': 'rotation'}}],
            'extras': {'markers': [{'time': 0.25, 'name': 'Quarter', 'value': 1}]},
        }
    ],
    'accessors': access,
    'bufferViews': views,
    'buffers': [{'byteLength': len(binary)}],
}
js = json.dumps(d).encode()
js += b' ' * ((-len(js)) % 4)
p = Path('assets/models/examples/skinRibbon.glb')
p.write_bytes(
    struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binary))
    + struct.pack('<II', len(js), 0x4E4F534A)
    + js
    + struct.pack('<II', len(binary), 0x004E4942)
    + binary
)
d['buffers'][0]['uri'] = 'skinRibbon.bin'
p.with_suffix('.gltf').write_text(json.dumps(d))
p.with_suffix('.bin').write_bytes(binary)
