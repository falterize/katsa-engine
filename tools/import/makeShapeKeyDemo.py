#!/usr/bin/env python3
"""Builds a small glTF binary (.glb) with named morph targets (Blender "Shape Keys").

The mesh is a UV sphere ("blob") with four shapes: Squash, Stretch, Spike and Twist.
No third-party packages are needed. Usage:

    python tools/import/makeShapeKeyDemo.py [output.glb]

To get the same model as a .blend file run it inside Blender instead:

    blender --background --python tools/import/makeShapeKeyDemo.py -- shapeKeys.blend
"""
import json
import math
import struct
import sys

RINGS = 16
SEGMENTS = 24

SHAPES = ['Squash', 'Stretch', 'Spike', 'Twist']


def baseMesh():
    positions = []
    for r in range(RINGS + 1):
        phi = math.pi * r / RINGS
        for s in range(SEGMENTS + 1):
            theta = 2 * math.pi * s / SEGMENTS
            positions.append(
                (math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
            )
    indices = []
    for r in range(RINGS):
        for s in range(SEGMENTS):
            a = r * (SEGMENTS + 1) + s
            b = a + SEGMENTS + 1
            indices += [a, b, a + 1, a + 1, b, b + 1]
    return positions, indices


def shapePositions(name, p):
    x, y, z = p
    if name == 'Squash':
        return (x * 1.5, y * 0.5, z * 1.5)
    if name == 'Stretch':
        return (x * 0.7, y * 1.6, z * 0.7)
    if name == 'Spike':
        k = 1.0 + 0.9 * max(0.0, math.sin(4 * math.atan2(z, x))) * (1 - abs(y))
        return (x * k, y, z * k)
    angle = y * 1.6
    c, s = math.cos(angle), math.sin(angle)
    return (x * c - z * s, y, x * s + z * c)


def normals(positions, indices):
    result = [[0.0, 0.0, 0.0] for _ in positions]
    for i in range(0, len(indices), 3):
        a, b, c = (positions[indices[i + k]] for k in range(3))
        u = [b[k] - a[k] for k in range(3)]
        v = [c[k] - a[k] for k in range(3)]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        for k in range(3):
            for idx in indices[i:i + 3]:
                result[idx][k] += n[k]
    for n in result:
        length = math.sqrt(sum(c * c for c in n)) or 1.0
        for k in range(3):
            n[k] /= length
    return result


def buildGlb(path):
    positions, indices = baseMesh()
    baseNormals = normals(positions, indices)
    chunks = []
    views = []
    accessors = []

    def add(data, target, kind, ctype, count, extra=None):
        while len(b''.join(chunks)) % 4:
            chunks.append(b'\0')
        offset = len(b''.join(chunks))
        chunks.append(data)
        views.append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(data), **({'target': target} if target else {})})
        accessor = {'bufferView': len(views) - 1, 'componentType': ctype, 'count': count, 'type': kind}
        if extra:
            accessor.update(extra)
        accessors.append(accessor)
        return len(accessors) - 1

    flat = [c for p in positions for c in p]
    lo = [min(p[k] for p in positions) for k in range(3)]
    hi = [max(p[k] for p in positions) for k in range(3)]
    pos = add(struct.pack('<%df' % len(flat), *flat), 34962, 'VEC3', 5126, len(positions), {'min': lo, 'max': hi})
    nor = add(struct.pack('<%df' % len(flat), *[c for n in baseNormals for c in n]), 34962, 'VEC3', 5126, len(positions))
    idx = add(struct.pack('<%dH' % len(indices), *indices), 34963, 'SCALAR', 5123, len(indices))
    targets = []
    for name in SHAPES:
        moved = [shapePositions(name, p) for p in positions]
        deltas = [c for p, m in zip(positions, moved) for c in (m[0] - p[0], m[1] - p[1], m[2] - p[2])]
        movedNormals = normals(moved, indices)
        normalDeltas = [c for n, m in zip(baseNormals, movedNormals) for c in (m[0] - n[0], m[1] - n[1], m[2] - n[2])]
        dlo = [min(deltas[k::3]) for k in range(3)]
        dhi = [max(deltas[k::3]) for k in range(3)]
        targets.append({
            'POSITION': add(struct.pack('<%df' % len(deltas), *deltas), 34962, 'VEC3', 5126, len(positions), {'min': dlo, 'max': dhi}),
            'NORMAL': add(struct.pack('<%df' % len(normalDeltas), *normalDeltas), 34962, 'VEC3', 5126, len(positions)),
        })
    blob = b''.join(chunks)
    document = {
        'asset': {'version': '2.0', 'generator': 'katsa makeShapeKeyDemo'},
        'scene': 0,
        'scenes': [{'nodes': [0]}],
        'nodes': [{'name': 'Blob', 'mesh': 0}],
        'meshes': [{
            'name': 'Blob',
            'primitives': [{'attributes': {'POSITION': pos, 'NORMAL': nor}, 'indices': idx, 'targets': targets, 'material': 0}],
            'weights': [0.0] * len(SHAPES),
            'extras': {'targetNames': SHAPES},
        }],
        'materials': [{'name': 'Blob', 'pbrMetallicRoughness': {'baseColorFactor': [0.35, 0.65, 0.95, 1.0], 'metallicFactor': 0.0, 'roughnessFactor': 0.6}}],
        'bufferViews': views,
        'accessors': accessors,
        'buffers': [{'byteLength': len(blob)}],
    }
    text = json.dumps(document, separators=(',', ':')).encode()
    text += b' ' * (-len(text) % 4)
    blob += b'\0' * (-len(blob) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(text), 0x4E4F534A) + text)
        f.write(struct.pack('<II', len(blob), 0x004E4942) + blob)


def buildBlend(path):
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    positions, indices = baseMesh()
    faces = [tuple(indices[i:i + 3]) for i in range(0, len(indices), 3)]
    mesh = bpy.data.meshes.new('Blob')
    mesh.from_pydata(positions, [], faces)
    mesh.update()
    obj = bpy.data.objects.new('Blob', mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.shape_key_add(name='Basis')
    for name in SHAPES:
        key = obj.shape_key_add(name=name)
        for i, p in enumerate(positions):
            key.data[i].co = shapePositions(name, p)
    bpy.ops.wm.save_as_mainfile(filepath=path)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    target = args[0] if args else 'shapeKeys.glb'
    if target.endswith('.blend'):
        buildBlend(target)
    else:
        buildGlb(target)
    print('wrote', target)
