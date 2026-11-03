"""Builds a core-GLB car from an FBX through the ufbx C dumper (no Blender, no Python ufbx).

    gcc -O1 -I<ufbx dir> tools/import/fbxDump.c <ufbx dir>/ufbx.c -lm -o /tmp/fbxDump
    /tmp/fbxDump Duke_69.fbx > duke.json
    python tools/import/fbxCarToGlb.py duke.json textures/ out.glb

Output conventions (the multiplayerCars scene relies on them):
  * Scene car space: the car faces +z, +x is its right side, y is up, the origin is on the ground
    below the chassis centre, so the model is instantiated without any extra rotation.
  * Body parts keep their names and carry car-space vertices (dents are computed in car space).
  * Each wheel is a node named Wheel_FL/FR/RL/RR at its hub with a hub-centred mesh, wheel axis = x.
  * Textures are resized and embedded; the body paint has no texture (the game tints it).
"""

import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image

WHEELS = ('WhellStock_FL', 'WhellStock_FR', 'WhellStock_RL', 'WhellStock_RR')
# material -> (texture file, size, alpha mode, base color factor)
MATERIALS = {
    'Duke69_bodymat': ('paint', None, 'OPAQUE', (1, 1, 1, 1)),
    'UCB_BOTTOM_LT': ('UCB_BOTTOM_LT_DIF.jpg', 512, 'OPAQUE', (1, 1, 1, 1)),
    'UCB_Interiors_2': ('UCB_Interiors_2_Dif.jpg', 512, 'OPAQUE', (1, 1, 1, 1)),
    'UCB_Lights_and_Glass': ('UCB_Lights_and_Glass_Dif.jpg', 512, 'OPAQUE', (1, 1, 1, 1)),
    'UCB_Lights_and_Glass_Transperent': (None, None, 'BLEND', (0.09, 0.13, 0.17, 0.55)),
    'RB1c_Tire_1k': ('RB1c_Tire_1k_Dif.jpg', 512, 'OPAQUE', (1, 1, 1, 1)),
    'Numberplates_Misk_U': ('Numberplates_Misk_U_Dif.png', 256, 'MASK', (1, 1, 1, 1)),
    'Carbadges_misc_U': ('Carbadges_misc_U_dif.png', 512, 'MASK', (1, 1, 1, 1)),
}


def rotate(p):
    """FBX car faces +x with its right side on +z; the scene car space faces +z with +x to the
    right. A pure rotation about y (no mirroring): (x, y, z) -> (-z, y, x)."""
    return (-p[2], p[1], p[0])


def main(dump, textures, output):
    data = json.load(open(dump))
    binary = bytearray()
    views, accessors, images, textures_out, materials, material_index = [], [], [], [], [], {}

    def add_view(blob):
        while len(binary) % 4:
            binary.append(0)
        views.append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(blob)})
        binary.extend(blob)
        return len(views) - 1

    def add_accessor(values, count, kind, bounds=False):
        blob = struct.pack('<%df' % len(values), *values)
        accessor = {'bufferView': add_view(blob), 'componentType': 5126, 'count': count, 'type': kind}
        if bounds:
            xs, ys, zs = values[0::3], values[1::3], values[2::3]
            accessor['min'], accessor['max'] = [min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)]
        accessors.append(accessor)
        return len(accessors) - 1

    def material(name):
        if name in material_index:
            return material_index[name]
        file, size, mode, factor = MATERIALS[name]
        pbr = {'baseColorFactor': list(factor), 'metallicFactor': 0.0, 'roughnessFactor': 0.8}
        if file and file != 'paint':
            image = Image.open(Path(textures) / file)
            if size and image.width > size:
                image = image.resize((size, size), Image.LANCZOS)
            buffer = io.BytesIO()
            if image.mode == 'RGBA':
                image.save(buffer, 'PNG', optimize=True)
                mime = 'image/png'
            else:
                image.convert('RGB').save(buffer, 'JPEG', quality=86)
                mime = 'image/jpeg'
            images.append({'bufferView': add_view(buffer.getvalue()), 'mimeType': mime})
            textures_out.append({'source': len(images) - 1, 'sampler': 0})
            pbr['baseColorTexture'] = {'index': len(textures_out) - 1}
        entry = {'name': name, 'pbrMetallicRoughness': pbr, 'alphaMode': mode, 'doubleSided': mode != 'OPAQUE'}
        if mode == 'MASK':
            entry['alphaCutoff'] = 0.5
        materials.append(entry)
        material_index[name] = len(materials) - 1
        return material_index[name]

    nodes, meshes, children = [], [], []
    for part in data['nodes']:
        name = part['name'].replace('Duke69_', '')
        p = part['p']
        points = [rotate(p[i : i + 3]) for i in range(0, len(p), 3)]
        normals = [rotate(part['n'][i : i + 3]) for i in range(0, len(p), 3)]
        offset = (0.0, 0.0, 0.0)
        node = {'name': name}
        if name in WHEELS:
            xs = [q[0] for q in points]
            ys = [q[1] for q in points]
            zs = [q[2] for q in points]
            offset = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2)
            points = [(q[0] - offset[0], q[1] - offset[1], q[2] - offset[2]) for q in points]
            # Named by car-space side: x < 0 is the left wheel, z > 0 the front one.
            label = ('F' if offset[2] > 0 else 'R') + ('L' if offset[0] < 0 else 'R')
            node = {'name': 'Wheel_' + label, 'translation': [round(v, 5) for v in offset]}
        uv = part['uv']
        flat_uv = []
        for i in range(0, len(uv), 2):
            flat_uv += [uv[i], 1.0 - uv[i + 1]]  # FBX v runs up, glTF v runs down
        flat_p = [c for q in points for c in q]
        flat_n = [c for q in normals for c in q]
        primitive = {
            'attributes': {
                'POSITION': add_accessor(flat_p, len(points), 'VEC3', True),
                'NORMAL': add_accessor(flat_n, len(points), 'VEC3'),
                'TEXCOORD_0': add_accessor(flat_uv, len(points), 'VEC2'),
            },
            'material': material(part['material']),
            'mode': 4,
        }
        meshes.append({'name': node['name'], 'primitives': [primitive]})
        node['mesh'] = len(meshes) - 1
        nodes.append(node)
        children.append(len(nodes))  # root is node 0
    document = {
        'asset': {'version': '2.0', 'generator': 'katsa fbxCarToGlb'},
        'scene': 0,
        'scenes': [{'nodes': [0]}],
        'nodes': [{'name': 'Car', 'children': children}] + nodes,
        'meshes': meshes,
        'materials': materials,
        'images': images,
        'textures': textures_out,
        'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
        'accessors': accessors,
        'bufferViews': views,
        'buffers': [{'byteLength': len(binary)}],
    }
    if not images:
        del document['images'], document['textures']
    body = json.dumps(document, separators=(',', ':')).encode()
    while len(body) % 4:
        body += b' '
    while len(binary) % 4:
        binary.append(0)
    total = 12 + 8 + len(body) + 8 + len(binary)
    Path(output).write_bytes(
        struct.pack('<4sII', b'glTF', 2, total)
        + struct.pack('<I4s', len(body), b'JSON') + body
        + struct.pack('<I4s', len(binary), b'BIN\0') + bytes(binary)
    )
    print('wrote', output, total, 'bytes', len(nodes), 'parts', len(images), 'textures')


if __name__ == '__main__':
    main(*sys.argv[1:4])
