# Editable and image-derived collision geometry

All geometry is baked only when its authored inputs change. Visual meshes and
images remain independent of their collision approximations. Keep original
geometry immutable and use copied point tables for manual changes.

## Manual Collider2D points

```lua
local collider = scene.ui:create('Collider2D', {
    shape = 'Polygon',
    points = {
        { -30, -30 }, { 30, -30 }, { 30, -10 },
        { -5, -10 }, { -5, 30 }, { -30, 30 },
    },
}, body2D)
collider.points[2][1] = 45
```

A flat list `{ x1, y1, x2, y2, ... }` is also accepted. `vertices` remains an alias
when points is absent. Coordinates are collider-local world units; position and
rotation then place the collider in its Body2D. Use an ordered, non-intersecting
polygon boundary without a duplicate closing point. Concave polygons and convex
polygons above eight vertices are triangulated into valid Box2D fixtures.
`collider:setPoints(points)` validates and selects Polygon mode. In-place edits
to nested coordinate tables are observed.

Edge and Chain use flat `vertices`; a Chain can set `loop = true`. A Compound
descriptor supplied to Body2D uses a children array of primitive descriptors.
Multiple Collider2D nodes are usually easier to inspect and edit.

## Collider2D from an image

```lua
scene.ui:create('Collider2D', {
    shape = 'Image',
    image = 'scene://textures/platform.png',
    size = { 256, 128 },
    collisionLevel = 'Detailed',
    imageResolution = 128,
    alphaThreshold = 0.5,
    maxFixtures = 1024,
}, body2D)
```

Paths use the normal scene/shared asset resolver: `shared://textures/...`,
`scene://textures/...`, project-relative paths or registered asset names.
`imagePath` is accepted when image is absent. Only alpha above alphaThreshold is
solid; RGB does not determine collision. Fully transparent images are invalid.
Position/rotation apply after the original image rectangle maps to size.

| collisionLevel | Approximation |
| --- | --- |
| Simple | One box around the opaque pixel bounds |
| Convex | Convex hull of occupied cells; fills concavities and holes |
| Detailed | Non-overlapping filled rectangles preserving occupied cells, holes and disconnected islands |

imageResolution limits the number of sampled cells along the longest image
dimension. Every source alpha pixel is examined once, so coarse cells retain thin
features conservatively; holes smaller than a cell can close. Raise resolution
for accuracy or lower it for fewer fixtures. Detailed supports Dynamic as well
as Static bodies because each piece is convex. Explicit maxFixtures prevents an
unexpectedly complex image from allocating an unbounded set of fixtures.

Decoded pixels are released after baking. Normalized geometry is cached on the
descriptor and reused when only collider size/position/rotation changes. Asset
contents are treated as immutable; increment `imageRevision` to reload a file
edited at the same path. This system builds collision shapes; it does not add an
image widget or change the underlying texture.

## Manual Collider3D points

```lua
local collider = scene.world:create('Collider3D', {
    shape = 'Points',
    collisionLevel = 'Convex',
    points = {
        { -1, 0, -1 }, { 1, 0, -1 },
        { 0, 0, 1 }, { 0, 2, 0 },
    },
}, body3D)
collider.points[4][2] = 3
```

`points` accepts nested XYZ coordinates or a flat XYZ list; `vertices` is accepted
when points is absent. The Simple level makes a bounding box, Convex builds a
convex hull, and Detailed makes the existing thin triangular-prism approximation
for static geometry. Coplanar Convex points receive the same thin extrusion as
mesh-derived convex geometry. Degenerate point clouds are rejected.

Detailed requires a Static Body3D and triangle topology. Set `indices` to a flat
list of one-based point indices in triples, or omit indices and supply a triangle
soup with three consecutive points per triangle. Arbitrary point clouds have no
unique surface connectivity. maxTriangles applies to the baked geometry.

## Extract, edit and bake a mesh

```lua
local points, indices = collider:getPointsFromMesh(mesh)
for _, point in ipairs(points) do
    if point[2] > 0 then
        point[1] = point[1] + 0.4
    end
end
collider:setPoints(points, indices)
```

`getPointsFromMesh(source, options)` accepts a Mesh3D or Node3D subtree in the
same world, or an OBJ/GLB/glTF model path, and returns independently owned points
plus triangle indices. World
transforms, mesh size and local mesh transforms are baked into the Body3D's local
coordinate frame. Collider position/rotation can then apply an additional local
offset. Equal positions are welded, using weldEpsilon (default 0.000001).
maxTriangles defaults to the collider budget (4096 initially) and can be passed
in the extraction options. File extraction accepts a local scale Vector3; the
collider methods default it to collider.size. Node sources use their hierarchy
transforms instead.

Equivalent entry points:

```lua
local Physics3D = require('source.engine.physics.3d')
local points, indices = mesh:getCollisionPoints(body3D)
local points, indices = Physics3D.extractMeshPoints(mesh, body3D)
collider:setPointsFromMesh(mesh)
```

File-oriented names use the same extraction implementation:

```lua
local points, indices = collider:getPointsFromModel('scene://models/collision.glb', {
    scale = { 2, 2, 2 },
    maxTriangles = 4096,
})
points[1][2] = points[1][2] + 0.25
collider:setPoints(points, indices)

-- Or bake directly; this selects Points and copies coordinates/topology.
collider:setPointsFromModel('shared://models/examples/pyramid.obj')

-- Omitting source uses the collider's current geometrySource.
local points, indices = collider:getPointsFromModel()
```

The Mesh/Model method names accept either source type for convenience. Explicit
physics-facade extraction also accepts paths; pass options.scale when needed.
Loading points does not instantiate render nodes or alter the source file.
Invalid explicit extraction raises a Lua error; wrap it in pcall for user input.

`setPoints` copies its input coordinates and indices, selects Points mode, and
leaves the mesh untouched. Editing `collider.points` afterwards rebuilds only its
collision geometry at the next node update. An invalid rebuild keeps the last
valid Collider3D descriptor and reports the error in status. This is a baked
snapshot of mesh geometry, not a per-frame skinned collision mesh or an automatic
link to future mesh edits. Re-extract explicitly when desired. Existing Geometry
mode with geometrySource retains its automatic source-tracking behavior.

The mixed Physics 2D + 3D example demonstrates an image with a transparent hole,
a manually authored concave polygon, and a 3D hull extracted and edited from a
mesh. Point authoring is a Lua API; no new graphical vertex-manipulation tool is
introduced by these methods.
