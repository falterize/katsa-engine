#!/usr/bin/env python3
"""Builds a small glTF binary (.glb) for the level-of-detail importer (test fixture and example).

  Rock, Rock-lod1, Rock-lod2   static meshes, three levels
  Body, Body-lod1              two skinned meshes on ONE skeleton (joints Root and Tip), with the
                               clip "Wave" that bends Tip: the animation plays whichever is shown

No third-party packages are needed. Usage: python tools/import/makeLodDemo.py [output.glb]
"""
import json
import math
import struct
import sys

# One triangle is enough: only node names, the skin and the clip matter here.
POSITIONS = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
INDICES = [0, 1, 2]


def build(path):
    chunks = []  # (bytes, target) pieces of the single buffer

    def view(data, target=None):
        while len(b''.join(c for c, _ in chunks)) % 4:
            chunks.append((b'\0', None))
        offset = len(b''.join(c for c, _ in chunks))
        chunks.append((data, target))
        views.append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(data)})
        if target:
            views[-1]['target'] = target
        return len(views) - 1

    views, accessors = [], []

    def accessor(index, component, count, kind, minimum=None, maximum=None):
        item = {'bufferView': index, 'componentType': component, 'count': count, 'type': kind}
        if minimum:
            item['min'], item['max'] = minimum, maximum
        accessors.append(item)
        return len(accessors) - 1

    flat = [value for p in POSITIONS for value in p]
    position = accessor(
        view(struct.pack('<9f', *flat), 34962), 5126, 3, 'VEC3',
        [min(p[i] for p in POSITIONS) for i in range(3)],
        [max(p[i] for p in POSITIONS) for i in range(3)],
    )
    index = accessor(view(struct.pack('<3H', *INDICES), 34963), 5123, 3, 'SCALAR')
    joints = accessor(view(bytes([0, 1, 0, 0] * 3), 34962), 5121, 3, 'VEC4')
    weights = accessor(view(struct.pack('<12f', *([0.5, 0.5, 0, 0] * 3)), 34962), 5126, 3, 'VEC4')
    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    bind = accessor(view(struct.pack('<32f', *(identity + identity))), 5126, 2, 'MAT4')
    times = accessor(view(struct.pack('<2f', 0.0, 1.0)), 5126, 2, 'SCALAR', [0.0], [1.0])
    half = math.sin(math.radians(30))
    rotations = accessor(
        view(struct.pack('<8f', 0, 0, 0, 1, 0, 0, half, math.cos(math.radians(30)))), 5126, 2, 'VEC4'
    )

    static = {'attributes': {'POSITION': position}, 'indices': index}
    skinned = {
        'attributes': {'POSITION': position, 'JOINTS_0': joints, 'WEIGHTS_0': weights},
        'indices': index,
    }
    nodes = [
        {'name': 'Rock', 'mesh': 0},
        {'name': 'Rock-lod1', 'mesh': 1},
        {'name': 'Rock-lod2', 'mesh': 2},
        {'name': 'Root', 'children': [4]},
        {'name': 'Tip', 'translation': [0, 1, 0]},
        {'name': 'Body', 'mesh': 3, 'skin': 0},
        {'name': 'Body-lod1', 'mesh': 4, 'skin': 0},
    ]
    document = {
        'asset': {'version': '2.0'},
        'scene': 0,
        'scenes': [{'nodes': [0, 1, 2, 3, 5, 6]}],
        'nodes': nodes,
        'meshes': [{'primitives': [static]} for _ in range(3)]
        + [{'primitives': [skinned]} for _ in range(2)],
        'skins': [{'joints': [3, 4], 'inverseBindMatrices': bind, 'skeleton': 3}],
        'animations': [
            {
                'name': 'Wave',
                'samplers': [{'input': times, 'output': rotations, 'interpolation': 'LINEAR'}],
                'channels': [{'sampler': 0, 'target': {'node': 4, 'path': 'rotation'}}],
            }
        ],
        'accessors': accessors,
        'bufferViews': views,
    }
    blob = b''.join(c for c, _ in chunks)
    document['buffers'] = [{'byteLength': len(blob)}]
    text = json.dumps(document, separators=(',', ':')).encode()
    text += b' ' * (-len(text) % 4)
    blob += b'\0' * (-len(blob) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    with open(path, 'wb') as out:
        out.write(struct.pack('<III', 0x46546C67, 2, total))
        out.write(struct.pack('<II', len(text), 0x4E4F534A) + text)
        out.write(struct.pack('<II', len(blob), 0x004E4942) + blob)


if __name__ == '__main__':
    build(sys.argv[1] if len(sys.argv) > 1 else 'lod.glb')
