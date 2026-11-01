"""Run with Blender 4.x: blender --background --python tools/import/convertModel.py -- input.fbx output.glb [--static]."""

import argparse
import json
import struct
import sys
from pathlib import Path
import bpy

parser = argparse.ArgumentParser(description='Convert desktop FBX/OBJ/GLB to Katsa core GLB.')
parser.add_argument('source', type=Path)
parser.add_argument('destination', type=Path)
parser.add_argument(
    '--static',
    action='store_true',
    help='Explicitly bake the current pose and discard all animation.',
)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1 :])
source = args.source.resolve()
destination = args.destination.resolve()
if not source.is_file():
    raise FileNotFoundError(source)
if destination.suffix.lower() != '.glb':
    raise ValueError('Destination must end in .glb')
bpy.ops.wm.read_factory_settings(use_empty=True)
extension = source.suffix.lower()
if extension == '.fbx':
    bpy.ops.import_scene.fbx(filepath=str(source))
elif extension == '.obj':
    bpy.ops.wm.obj_import(filepath=str(source))
elif extension in ('.glb', '.gltf'):
    bpy.ops.import_scene.gltf(filepath=str(source))
else:
    raise ValueError('Expected FBX, OBJ, GLB or glTF')
mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
if not mesh_objects:
    raise ValueError('Input contains no mesh objects')
if args.static:
    graph = bpy.context.evaluated_depsgraph_get()
    snapshots = []
    for obj in mesh_objects:
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(graph), depsgraph=graph)
        snapshots.append((obj.name, mesh, obj.matrix_world.copy()))
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for name, mesh, matrix in snapshots:
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.matrix_world = matrix
    print(
        'STATIC BAKE: hierarchy flattened; all animation and deformation removed at the current frame.'
    )
# The runtime imports base color; additional maps can be assigned via SurfaceAppearance3D.
for obj in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
    modifier = obj.modifiers.new('KatsaTriangulate', 'TRIANGULATE')
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for attribute in list(obj.data.color_attributes):
        raise ValueError('Vertex colors must first be baked to a base-color texture.')
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(destination),
    export_format='GLB',
    export_animations=not args.static,
    export_force_sampling=True,
    export_skins=not args.static,
    export_morph=False,
    export_cameras=False,
    export_lights=False,
    export_yup=True,
    export_texcoords=True,
    export_normals=True,
    export_materials='EXPORT',
    export_apply=False,
)
raw = destination.read_bytes()
length, kind = struct.unpack_from('<II', raw, 12)
document = json.loads(raw[20 : 20 + length])
if document.get('extensionsRequired'):
    destination.unlink()
    raise ValueError('Export requires unsupported required extensions; output removed.')
for animation in document.get('animations', []):
    for sampler in animation['samplers']:
        if sampler.get('interpolation', 'LINEAR') not in ('LINEAR', 'STEP', 'CUBICSPLINE'):
            destination.unlink()
            raise ValueError(
                'Export still contains non-linear animation. Bake animation to sampled LINEAR keys.'
            )
print(f'Converted: {destination}')
print(
    'Runtime imports base color and alpha. Assign additional material maps via SurfaceAppearance3D.'
)
