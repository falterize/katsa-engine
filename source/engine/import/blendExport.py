"""Runs inside Blender: blender --background --factory-startup <file.blend> --python blendExport.py -- <out.glb>

Exports the opened .blend as a GLB the Katsa runtime imports (same settings as
tools/import/convertModel.py). Modifiers are applied, animation is baked to sampled keys, and hidden
objects are exported too, so collision-only meshes named `...-colonly` survive. Exits non-zero on error.
"""

import json
import struct
import sys
from pathlib import Path

import bpy

try:
    destination = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(destination),
        export_format='GLB',
        export_animations=True,
        export_force_sampling=True,
        export_skins=True,
        export_morph=False,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_apply=True,
        use_visible=False,
    )
    raw = destination.read_bytes()
    length, _kind = struct.unpack_from('<II', raw, 12)
    document = json.loads(raw[20 : 20 + length])
    if document.get('extensionsRequired'):
        destination.unlink()
        raise ValueError('Export requires unsupported extensions: ' + ', '.join(document['extensionsRequired']))
    print('KATSA_BLEND_OK', destination)
except Exception as error:  # noqa: BLE001 - report every failure with a non-zero exit
    print('KATSA_BLEND_ERROR', error)
    sys.exit(1)
