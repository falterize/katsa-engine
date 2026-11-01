"""Offline FBX to core GLB conversion. Requires ufbx==0.0.5 and numpy.
Usage: python convertFbxUfbx.py input.fbx output.glb
Preserves named nodes, skinned mesh parts, bind matrices and sampled TRS clips.
Unsupported: morphs, constraints, PBR maps and embedded texture extraction.
"""

import json, struct, sys, math, os
from pathlib import Path
import numpy as np
import ufbx

source, destination = map(Path, sys.argv[1:3])
scene = ufbx.load_file(str(source))
# Keep all native proxy owners alive: nested temporary proxies in 0.0.5 are unsafe.
owners = [scene]


def keep(obj):
    owners.append(obj)
    return obj


nodes = list(keep(scene.nodes))
owners.extend(nodes)
node_ids = {n.element_id: i for i, n in enumerate(nodes)}
binary = bytearray()
views = []
accessors = []


def data(values, kind, component=5126):
    values = np.asarray(values, dtype={5126: '<f4', 5123: '<u2', 5125: '<u4'}[component])
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    binary.extend(values.tobytes())
    views.append({'buffer': 0, 'byteOffset': offset, 'byteLength': values.nbytes})
    accessors.append(
        {
            'bufferView': len(views) - 1,
            'componentType': component,
            'count': len(values),
            'type': kind,
        }
    )
    return len(accessors) - 1


def matrix(m):
    return [*m.c0, 0, *m.c1, 0, *m.c2, 0, *m.c3, 1]


def trs(t):
    return {
        'translation': list(t.translation),
        'rotation': list(t.rotation),
        'scale': list(t.scale),
    }


outnodes = []
for n in nodes:
    d = {'name': n.name or 'Root', **trs(n.local_transform)}
    children = list(keep(n.children))
    owners.extend(children)
    if children:
        d['children'] = [node_ids[c.element_id] for c in children]
    outnodes.append(d)
meshes = []
skins = []
materials = []
for ni, n in enumerate(nodes):
    mesh = keep(n.mesh)
    if mesh is None:
        continue
    attributes = [keep(mesh.vertex_position), keep(mesh.vertex_normal), keep(mesh.vertex_uv)]
    arrays = [(keep(a.values), keep(a.indices)) if a.exists else None for a in attributes]
    faces = list(keep(mesh.faces))
    index = keep(mesh.vertex_indices)
    skinlist = keep(mesh.skin_deformers)
    skin = keep(skinlist[0]) if len(skinlist) else None
    if skin:
        clusters = list(keep(skin.clusters))
        owners.extend(clusters)
        bones = [keep(c.bone_node) for c in clusters]
        inv = [matrix(c.geometry_to_bone) for c in clusters]
        skins.append(
            {
                'name': n.name + 'Skin',
                'joints': [node_ids[b.element_id] for b in bones],
                'inverseBindMatrices': data(inv, 'MAT4'),
            }
        )
        outnodes[ni]['skin'] = len(skins) - 1
        sv, sw = keep(skin.vertices), keep(skin.weights)
    positions = []
    normals = []
    uv = []
    joints = []
    weights = []
    for f in faces:
        for k in range(1, f.num_indices - 1):
            for corner in [f.index_begin, f.index_begin + k, f.index_begin + k + 1]:
                p = list(arrays[0][0][arrays[0][1][corner]])
                positions.append(p)
                normals.append(list(arrays[1][0][arrays[1][1][corner]]) if arrays[1] else [0, 1, 0])
                tex = list(arrays[2][0][arrays[2][1][corner]]) if arrays[2] else [0, 0]
                uv.append([tex[0], 1 - tex[1]])
                if skin:
                    vert = sv[index[corner]]
                    influences = sorted(
                        [
                            sw[j]
                            for j in range(vert.weight_begin, vert.weight_begin + vert.num_weights)
                        ],
                        key=lambda w: -w.weight,
                    )[:4]
                    total = sum(w.weight for w in influences) or 1
                    joints.append(
                        [w.cluster_index for w in influences] + [0] * (4 - len(influences))
                    )
                    weights.append(
                        [w.weight / total for w in influences] + [0] * (4 - len(influences))
                    )
    attrs = {
        'POSITION': data(positions, 'VEC3'),
        'NORMAL': data(normals, 'VEC3'),
        'TEXCOORD_0': data(uv, 'VEC2'),
    }
    if skin:
        attrs.update(JOINTS_0=data(joints, 'VEC4', 5123), WEIGHTS_0=data(weights, 'VEC4'))
    color = [0.65, 0.7, 0.8, 1] if 'Surface' in n.name else [0.08, 0.1, 0.13, 1]
    materials.append(
        {'name': n.name, 'pbrMetallicRoughness': {'baseColorFactor': color}, 'doubleSided': True}
    )
    meshes.append(
        {'name': n.name, 'primitives': [{'attributes': attrs, 'material': len(materials) - 1}]}
    )
    outnodes[ni]['mesh'] = len(meshes) - 1
animations = []
stacks = list(keep(scene.anim_stacks))
owners.extend(stacks)
for stack in stacks:
    anim = keep(stack.anim)
    duration = stack.time_end - stack.time_begin
    if duration <= 0 or duration > 120:
        continue
    frames = max(2, math.ceil(duration * 30) + 1)
    times = [i * duration / (frames - 1) for i in range(frames)]
    clip = {'name': stack.name or 'Take', 'channels': [], 'samplers': []}
    time_accessor = data([[t] for t in times], 'SCALAR')
    for i, n in enumerate(nodes):
        poses = [n.evaluate_transform(anim, t + stack.time_begin) for t in times]
        for path, field, kind in [
            ('translation', 'translation', 'VEC3'),
            ('rotation', 'rotation', 'VEC4'),
            ('scale', 'scale', 'VEC3'),
        ]:
            values = [list(getattr(t, field)) for t in poses]
            if all(np.max(np.abs(np.asarray(v) - values[0])) < 1e-5 for v in values):
                continue
            clip['samplers'].append(
                {'input': time_accessor, 'output': data(values, kind), 'interpolation': 'LINEAR'}
            )
            clip['channels'].append(
                {'sampler': len(clip['samplers']) - 1, 'target': {'node': i, 'path': path}}
            )
    if clip['channels']:
        animations.append(clip)
roots = [i for i, n in enumerate(nodes) if n.parent is None]
doc = {
    'asset': {'version': '2.0', 'generator': 'Katsa offline ufbx converter'},
    'scene': 0,
    'scenes': [{'nodes': roots}],
    'nodes': outnodes,
    'meshes': meshes,
    'skins': skins,
    'materials': materials,
    'animations': animations,
    'bufferViews': views,
    'accessors': accessors,
    'buffers': [{'byteLength': len(binary)}],
}
js = json.dumps(doc, separators=(',', ':')).encode()
js += b' ' * ((-len(js)) % 4)
binary += b'\0' * ((-len(binary)) % 4)
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(
    struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binary))
    + struct.pack('<II', len(js), 0x4E4F534A)
    + js
    + struct.pack('<II', len(binary), 0x004E4942)
    + binary
)
print(
    json.dumps(
        {
            'nodes': len(nodes),
            'meshes': len(meshes),
            'joints': [len(s['joints']) for s in skins],
            'animations': [(a['name'], len(a['channels'])) for a in animations],
            'output': str(destination),
        }
    ),
    flush=True,
)
# Prevent unsafe destruction of native temporary proxy owners in this wheel version.
os._exit(0)
