# Hierarchical models and skeleton animation

`world:loadModel(path, settings)` returns the named Node3D root, its model instance
and the flat list of render meshes. `Models.load` + `Models.instantiate` remain
available; instantiate returns the meshes first and the root second. Instances
own mutable poses, tracks and palettes; GPU geometry/textures use the resource cache.
Load a new instance to mount an asset twice. Destroying the root destroys its tracks,
bones, attachments and children. GPU assets remain cached under their resource scope.

```lua
local root, model = world:loadModel('assets/models/characters/xbot.glb', {
    name = 'PlayerModel',
    position = { 0, 0, 30 },
    scale = { 0.5, 0.5, 0.5 },
})
local surface = root:find('Beta_Surface', true) -- Named imported Node3D.
local hand = model.byNodeName['mixamorig:RightHand'].instance -- Bone3D.
local grip = world:create('Attachment3D', { name = 'WeaponGrip', position = { 0, 3, 0 } }, hand)
local track = model.animator:load('Walk') -- The clip must exist in this asset.
track.looped = true
track:play(0.2)
```

Imported scene hierarchy, node names, mesh primitives and material boundaries are
preserved. Mesh names carry the instance name because the existing World3D mesh
index requires global uniqueness. A source mesh may have several Mesh3D children
for material primitives or GPU bone palettes. Bone3D Position/Rotation/Scale are
additional local offsets after the imported pose; RestPosition/RestRotation/RestScale
show the immutable imported TRS. Rotation offsets are degrees; rest rotation is an
X/Y/Z/W quaternion. Source translations are preserved in source units. glTF is Y-up;
the engine camera faces +Z, so explicitly rotate assets authored with -Z forward.

Runtime supports OBJ/basic MTL, GLB and external glTF with one binary buffer. Static
materials retain base color/texture, alpha modes and double-sided state. This is a
diffuse renderer, not a complete PBR implementation. Required extensions, compression,
sparse accessors, morph targets, COLOR_0 and more than eight influences require offline
conversion. External glTF images use file paths; data-URI images need GLB conversion.
Meshes must use triangles. Animated nodes use TRS instead of a matrix.

## FBX conversion

FBX is an offline input, not a runtime importer. Blender preserves the rig and
samples export animation:

```bash
blender --background --python tools/import/convertModel.py -- input.fbx output.glb
# Explicit static-pose bake, discarding skeleton/animation:
blender --background --python tools/import/convertModel.py -- input.fbx output.glb --static
```

The supplied X Bot was converted using the optional offline helper:

```bash
python -m pip install ufbx==0.0.5 numpy
python tools/import/convertFbxUfbx.py input.fbx output.glb
```

This helper fan-triangulates polygon input (use Blender for concave polygons),
retains nodes, weights, bind matrices and sampled motion but uses neutral
base colors. It does not extract textures/PBR maps, morphs or constraints; Blender is
the general conversion path. Its pinned native wheel needs proxy-lifetime protection,
which is isolated to this offline script. No ufbx dependency runs inside katsa.
The supplied X Bot has two source meshes and skins with 65/64 joints. Its FBX takes
contain no usable motion. The six Demo clips are procedural example code, not Mixamo
animations. `skinRibbon.glb` and `.gltf` contain an actual imported two-bone Bend clip
with a marker. `cubeTriangle.glb` contains two independently accessible mesh nodes.

## Animator and AnimationTrack

Animator belongs to a model root. `animator:load(index/name/clip)` creates a track;
channels must refer to nodes of that instance. Wrong skeletons produce explicit
errors. Automatic humanoid retargeting and separately imported animation remapping
are not implemented: export the animation with the matching rig/model.

Track properties: `speed` (finite, including reverse), `looped`, `timePosition`
(seconds), `weight` (0..1), `priority` (higher wins), `boneMask` (node-name to 0..1).
An empty mask includes all nodes; a nonempty mask excludes unlisted nodes. Workspace
provides a bone list with include/exclude buttons and weight sliders. Channels not
present in a higher-priority track remain available to lower-priority tracks; unused
weight falls back to the rest pose. Rotations interpolate with shortest-path SLERP;
blends use normalized quaternion accumulation. STEP, LINEAR and CUBICSPLINE are
supported, including time-scaled cubic tangents and normalized cubic rotations.

`play(fadeSeconds)`, `pause()`, `resume()`, `stop(fadeSeconds)` and
`fade(weight, seconds)` control playback. Stop fades toward rest/lower tracks;
pause retains its weighted pose. `timePosition` can be assigned to seek. A non-loop
track emits Completed and holds its last weighted pose. Destroy it or stop it to
remove that contribution. `Started`, `Stopped`, `Completed`, `Marker` and
`Marker:name` use the existing node event API.

`animator:transition(name, seconds)` crossfades prepared states and reuses each
state track. Calling it again for the already playing state keeps playback intact.
State names and transition decisions belong to game code. Demo Idle/Walk/Run/Jump/
Fall/Wave show this; there is no built-in player state machine in the core.
`poseRate` defaults to 60 poses/second (1..240) of wall-clock time. Playback/markers advance
every world update at the World3D.TimeScale speed; pose evaluation follows the budget in real
time, so a slowed world still animates smoothly (see the [step smoothing guide](../animation/stepValue.md)).

## Markers, attachments and root motion

Author markers in glTF `animation.extras.markers` or a clip's Lua `markers` array:

```lua
clip.markers = { { time = 0.25, name = 'Footstep', value = 'Left' } } -- Time in seconds.
track:connect('Marker:Footstep', function(side)
    footstepSound:play()
end)
```

Markers cross playback intervals in either direction and across loops. A very large
single update dispatches at most 64 occurrences per marker. Attachment3D under Bone3D
uses the current hierarchy for weapons, cameras, sound and particles.

Root motion is opt-in: `animator.rootMotionEnabled=true`. The first active track with
root translation supplies movement; the matching translation is removed from the
bone pose to avoid applying movement twice. The first sample establishes a baseline.
Without physics, movement is rotated/scaled into the model root's parent coordinates.
With a physics ancestor, assign `rootMotionHandler(delta, animator, seconds)` and
resolve movement through your character/kinematic collision controller. Delta is in
asset-local units, before model scale/rotation. Do not silently teleport a dynamic
body; use the physics API and handle obstacles explicitly. This is a root-motion
integration foundation, not an automatic character motor.

## GPU skinning, bounds and debugging

Each primitive is partitioned into palettes of at most 32 joints with up to eight normalized
weights per vertex. The full skeleton is retained; palette splitting does not change
node paths. Vertex-only matrices avoid GLES cross-stage precision/layout mismatches.
Main and shadow shaders use the same weighted deformation before material hooks.
Instancing never shares one palette across independent model instances. Conservative
joint envelopes update animated culling bounds; changed palettes invalidate shadows.
Paused poses do not repeatedly invalidate their geometry. Bones with nonuniform scale
use the deformed normal matrix. This path requires the existing GLSL3 renderer; a CPU
skinning fallback is not supplied. Sparse/morph/dual-quaternion skins are unsupported.

`animator.debugEnabled=true` draws bones and bone Attachment lines in the render target,
including a ViewportFrame. Green lines are bones; orange points are joints; purple
lines mark attachments. It returns before allocating debug data when disabled.

Mesh colliders are independent Body3D/Collider3D nodes. Use the unscaled model frame
or explicitly bake model scale into a body, as shown in the collisionModels example.
Physics requires a rigid unscaled spatial parent (or explicit inheritScale=false).
The new model lab uses a convex cube and a thin triangular-prism collider for the
floating triangle. Dropped test cubes demonstrate the surfaces. Skinned vertex motion
does not automatically deform physics colliders. Precise animated triangle picking
still uses the rest geometry; use proxy colliders/targets for gameplay interaction.

References: [glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
and [Blender glTF exporter](https://docs.blender.org/api/current/bpy.ops.export_scene.html).
