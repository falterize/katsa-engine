# Models, opacity and surface materials — v64

See [the skeletal API](hierarchy.md) for tracks, masks, markers and root motion.

## Import hierarchy

`world:loadModel(path, settings)` returns `root, model, meshes`.
The named Node3D root groups the imported model and owns its lifetime/transform.
A source node with one render primitive becomes Mesh3D itself, preserving its
local pose and children. An identity, nonanimated, empty exporter root is omitted.
Groups with multiple material primitives or bone-palette batches stay Node3D;
bones stay Bone3D. A single mesh therefore has no intermediate Node3D wrapper.
Mesh names carry the instance name for the world index; use
`model.byNodeName.Cube.instance` to address the original source name.
Static assets create no Animator. Rigid animated assets keep an internal controller;
`model:play(index)` still works. Only skinned assets create an Animator node.

## Blender files (.blend)

`world:loadModel('assets/car.blend')` works like a GLB. Katsa asks the installed Blender to export
the file (modifiers applied, animation baked, hidden objects kept) and imports the result, the same
way Godot does. The first import takes a few seconds; the GLB is cached in the save directory
(`blend-cache/`, keyed by the file contents), so unchanged files load instantly afterwards.

- Blender 3.6 or newer is found through `KATSA_BLENDER` / `BLENDER`, `PATH`, or its usual install folder.
- **Shipping**: players do not have Blender. `python tools/build/packageKatsa.py --source <game> --convert-blend`
  stores `car.blend.glb` instead of `car.blend`; the runtime prefers that file. `python tools/import/blendToGlb.py car.blend`
  makes the same file by hand. This is the only way on Android.
- The same export settings as `tools/import/convertModel.py` apply: base color and alpha are imported,
  extra maps go through `SurfaceAppearance3D`, vertex colors must be baked to a texture.

## Collision from node names

Name objects in Blender (or any DCC tool) with a suffix and `Models.instantiate` / `world:loadModel`
builds the physics for you when the world has physics (`autoCollision = false` in the settings turns
it off; `settings.friction`, `restitution`, `collisionGroup` and `collisionLevel` tune the bodies):

| Name | Result |
| --- | --- |
| `wall-col` | the mesh keeps rendering and gets an exact (`Detailed`) static `Body3D` + `Collider3D` |
| `wall-colonly` | the mesh is hidden (`visible = false`) and is used for collision only |

With `-colonly`, if another mesh node is named `wall`, the collider attaches to that node and moves
with it (`apple` + `apple-colonly`); with no such node it is an invisible collision object at its own
place. Matching ignores letter case and Blender's `.001` copy suffix. The created bodies are listed
in `model.collisionBodies`. Works for GLB, glTF, OBJ object names and `.blend`.

## Node3D.Transparency

Range 0..1, default 0. Opacity is the product of `1-Transparency` over a node and
all Node3D ancestors. A parent at .5 and child at .4 yield opacity .3.
Child properties are never overwritten. Meshes, particles and spatial UI inherit
this opacity; fully transparent meshes leave render/picking/shadow selection.
Physics, transforms, animation and attachments continue updating. Screen World2D
uses its existing UI transparency rules rather than spatial group opacity.

## SurfaceAppearance3D

Place one enabled SurfaceAppearance3D directly under a Mesh3D. Enabled=false
restores that mesh's original material. Paths can be project paths or registered
image assets. Empty paths omit a map. Images use the mesh's TEXCOORD_0.

```lua
local cube = model.byNodeName.Cube.instance
world:create('SurfaceAppearance3D', {
    normalMap = 'assets/textures/materials/normal.png',
    roughnessMap = 'assets/textures/materials/roughness.png',
    metalnessMap = 'assets/textures/materials/metal.png',
    emissionMap = 'assets/textures/materials/emission.png',
    roughness = 0.45,
    metalness = 0.35,
    emissionStrength = 1,
    pixelate = false,
}, cube)
root.Transparency = 0.5
```

| Property | Meaning |
| --- | --- |
| ColorMap | Replaces base-color image; Color multiplies RGB |
| NormalMap / NormalScale | Tangent-space RGB normal, positive Y; strength >=0 |
| RoughnessMap / Roughness | Red channel times factor 0..1 |
| MetalnessMap / Metalness | Red channel times factor 0..1 |
| OcclusionMap / OcclusionStrength | Red ambient-occlusion channel, strength 0..1 |
| EmissionMap / EmissionColor / EmissionStrength | RGB emission added before tone mapping; strength >=0 |
| Pixelate | Independent nearest sampling for this appearance's maps |
| AlphaMode | Inherit original mode, Opaque, Mask, or Blend |
| AlphaCutoff | Mask threshold 0..1; appears only in Mask mode |

Lua field names use lower camel case; standard Pascal aliases are supported for
ColorMap, NormalMap, RoughnessMap, MetalnessMap, EmissionMap and EmissionStrength.
Use the lower camel names for other fields. Alpha participates in shadow masking.
Derivative tangent frames work with GPU-deformed geometry; meshes need UVs and normals.
The renderer approximates roughness/metalness using direct-light specular shading.
There is no image-based lighting, displacement, parallax or full glTF PBR fidelity.
Additional imported glTF material maps must currently be assigned explicitly.

## Fast loading

The XBot GLB includes `xbot.glb.kmesh`, a build-time binary sidecar. It stores the
normalized vertex/palette layout and conservative skin envelopes. GPU assets are
shared, while instance poses/tracks are independent. CPU vertex arrays are decoded
lazily only for CPU geometry consumers such as convex-collider creation.
The loader checks SHA-256 of the source and ignores a stale sidecar. GLB/glTF and
OBJ still load directly without it. `katsa . --bake-xbot` rebuilds this specific
neutral-material demo cache. The current builder does not serialize embedded
texture handles; this is an optional optimization, not a general model converter.

## FBX conversion with Blender

FBX requires offline conversion; OBJ is static geometry and cannot preserve bones.
GLB/glTF can be loaded directly, including skins and supported animation clips.
On a desktop with Blender 4.x:

1. File > Import > FBX; select the model. Check the armature and animation actions.
2. File > Export > glTF 2.0. Select GLB (binary).
3. Export meshes, UVs, normals and materials. Enable Skinning and Animations.
   Disable morph targets; bake/sample animation keys. If several actions are needed,
   export them as actions or NLA tracks and verify the resulting clip names.
4. Place the GLB in assets and load it with `world:loadModel`.

Alternatively, from the project root:

```sh
blender --background --python tools/import/convertModel.py -- character.fbx assets/models/character.glb
```

Do not add `--static` for a rig: it deliberately removes bones/animation.
Mixamo downloads without animation contain a skeleton but no motion clip. Download
separate animation-bearing assets to obtain real clips; loading a skeleton does not
create Idle/Walk automatically. The included XBot states are procedural examples.
Blender conversion was not executed in this update because Blender is unavailable.
