# Spatial transforms (v45)

All spatial nodes use local `position`, `rotation` and `scale`. Folders contribute
no transform; the nearest spatial ancestor supplies the parent matrix. Ordinary
Node3D descendants inherit the complete affine matrix. Changes to numeric vector
components are detected without setter calls. Cached matrices/revisions remain
unchanged for unchanged poses, including stationary physics synchronization.

`Mesh3D.size` supplies geometry dimensions, independently of the spatial pose.
The mesh render matrix combines spatial scale with those dimensions. Its children
inherit `scale`, never `size`. Imported model `size` remains a multiplier for asset
geometry/internal node offsets; `settings.scale` supplies instance spatial scale.
An imported part's internal `localMatrix` belongs to asset geometry/rigid animation;
children attach to its instance origin. Skeletal/bone sockets are a later stage.

## Coordinates and units

- +X is right, +Y is up, +Z is forward. Distances use project-defined world units.
- Euler properties use degrees, with `Rz(roll) * Ry(-yaw) * Rx(pitch)` acting on
  column vectors: X, then negative Y, then Z. Existing position/yaw/pitch behavior
  is retained. Camera3D properties retain their existing opposite pitch/yaw signs:
  camera matrices use `Rz(roll) * Ry(yaw) * Rx(-pitch)`.
- Camera3D roll now works consistently even when directly parented to World3D or
  unparented. Projection always extracts a rigid camera frame.
- CFrame angular constructors use radians; CFrame is a rigid pose, without scale.
- Matrices are row-major arrays of 16 values acting on column vectors.
  Translation occupies indices 4, 8 and 12. The final row is 0,0,0,1.
- `scale` is dimensionless and each component must exceed 0.000001. Zero,
  negative/mirrored scales and perspective pose matrices are unsupported.
- Physics defaults to 20 world units per meter; `unitsPerMeter` is configurable.
  Light ranges, camera clipping/focal settings, audio attenuation and stereo width
  remain independent world-unit settings, not multiplied by a node's scale.

Attachment3D defaults to `inheritScale = false`: its position/rotation inherit the
parent's rigid frame, so parent scale does not enlarge socket offsets. Set
`inheritScale = true` to inherit scale normally. Any spatial node can opt out.
BillboardUI retains its own existing opt-in `inheritScale` behavior; its `size` is
UI width/height in its selected size mode. Spatial scale affects the anchor pose,
not UI layout or panel dimensions. Sound voices follow the same world position;
listener orientation follows the active camera. Dedicated Sound nodes are pending.

## API

| API | Behavior |
| --- | --- |
| `getLocalMatrix(out?)`, `getWorldMatrix()` | Local matrix copy; cached world matrix (treat as read-only) |
| `getLocalTransform()`, `getWorldTransform()` | New `{position, rotation, scale}` tables, Euler values in degrees |
| `setLocalTransform(pose)` | Partial position/rotation/scale update; copies supplied vectors |
| `setWorldTransform(pose)` | Full position/rotation, optional scale defaulting to 1; resolves parent |
| `setLocalMatrix(matrix)`, `setWorldMatrix(matrix)` | Decomposes and assigns a representable TRS pose |
| `getWorldCFrame()` | Rigid world pose, excludes geometry dimensions and spatial scale |
| `setCFrame(frame)` | Local rigid pose; preserves local scale |
| `setWorldCFrame(frame)` | World3D rigid pose; preserves current world scale |
| `pointToWorldSpace(point, out?)`, `pointToLocalSpace(point, out?)` | Affine point conversion, including translation |
| `vectorToWorldSpace(vector, out?)`, `vectorToLocalSpace(vector, out?)` | Linear vector/direction conversion, no translation; retains scale |
| `setParent(parent, {keepWorldTransform=true})` | Preserves world matrix; validates new local pose before committing |

Vectors use the existing three-component arrays/Vector3. Normalize converted
vectors explicitly if a unit direction is required. Getter/setter TRS operations
may return equivalent Euler angles rather than the original numeric angles.
Direct `parent = newParent` and `setParent(newParent)` preserve the local pose.
A `parentChanged` listener observes the final preserved pose. Ownership/cycle/
body/UI rules from `nodeLifecycle.md` still apply.

Nonuniform scale plus rotated descendants can produce shear. Affine rendering
and point/vector conversion support it. TRS decomposition, keep-world reparent,
CFrame extraction, scale exclusion and camera rigid-frame extraction reject shear
with a clear error instead of silently losing it. Reparent failures preserve the
old parent and properties. Use uniform ancestor scale or a separate socket branch
when a rigid pose is required.

## Physics constraints

Bodies remain in World3D space, with organizational Folder ancestors only. World3D
must remain untransformed while physics is active. Creation rejects a transformed
root or nonuniform body scale. Positive uniform body scale is applied exactly once
to collider dimensions and collider offsets. Body and collider rotations use the
same engine Euler convention. Teleport uses the same matrix as rendering.

Use transform setters or `body:teleport` to move a body; direct edits to physics
`position`/`rotation` arrays are overwritten by solver synchronization. Size/scale
are immutable while a body exists: destroy and recreate the body to change them.
Workspace rejects live-body size/scale edits. Queries use the solver broadphase;
after a teleport, allow the next fixed physics step to synchronize its query tree.
The bundled Oimo BVH now also synchronizes a world containing only one collider.

## Migration and example

Existing independent meshes keep their visual dimensions. If old code used a
parent's `size` to scale child offsets, move that inherited factor into `scale`.
Do not copy the same factor into both fields unless the extra multiplication is
intentional. If collider rotation relied on Oimo's former raw positive XYZ Euler
interpretation, convert it to the documented engine convention.

```lua
local pivot = world:create('Node3D', {
    name = 'Pivot',
    position = { 10, 0, 0 },
    rotation = { 0, 90, 0 },
    scale = { 2, 2, 2 },
})
local mesh = world:create('Mesh3D', {
    name = 'Box',
    position = { 0, 0, 3 },
    size = { 4, 6, 8 },
}, pivot)
local socket = world:create('Attachment3D', {
    name = 'ToolSocket',
    position = { 0, 4, 0 },
    inheritScale = true,
}, mesh)
local point = socket:pointToWorldSpace({ 0, 0, 1 })
mesh:setParent(world.folders.Geometry, { keepWorldTransform = true })
mesh:setWorldTransform({ position = point, rotation = { 0, 0, 0 }, scale = { 2, 2, 2 } })
```
