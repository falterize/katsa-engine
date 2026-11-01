# Collider3D and attachment constraints

Collider3D is a child of Body3D. Use shape="Geometry", geometrySource pointing to
one Mesh3D, a whole Node3D model, or a model file path, and
collisionLevel="Simple", "Convex" or "Detailed".
Simple creates a box for each mesh; Convex creates a hull per mesh; Detailed creates
thin triangle prisms and requires a Static body. maxTriangles bounds Detailed work.
Convex is not automatic decomposition of an individual concave mesh. Skinned models
use bind geometry, not live GPU vertex deformation. Source transforms and geometry
changes rebuild cached shapes; stable geometry reuses them. Status reports invalid
or unavailable sources. Primitive Box/Sphere/Capsule/Cylinder remain available.

## Model files

Geometry sources accept OBJ, GLB and glTF through the common model importer.
Paths support `scene://`, `shared://` and project-relative resources, including
resources inside a mounted scene archive. glTF external buffers/textures remain
relative to the glTF file. Existing importer restrictions and sidecars still apply.

```lua
local collider = scene.world:create('Collider3D', {
    shape = 'Geometry',
    geometrySource = 'shared://models/examples/pyramid.obj',
    size = { 2, 2, 2 },
    collisionLevel = 'Convex',
}, body)
```

For a file source, Size multiplies the model's authored local dimensions; embedded
node transforms are preserved. For a node reference, dimensions come from the
source hierarchy as before. Collider Position and Rotation apply once as an
additional body-local offset in both cases. File collision uses the imported rest
geometry and does not follow skeletal animations.

Workspace's GeometrySource picker includes a Model path TextBox above the node
list. Enter a supported file path and confirm, or choose a live node. An empty
source disables that explicit collider until a source is assigned. Invalid file
edits report status and keep the last valid collider. Failed loads are cached;
change the source or reload the scene after repairing a previously invalid file.
No missing-model visual cube is substituted for collision.

Files are loaded once per source, with resources shared by the scene scope.
Stable sources reuse collected geometry and native shapes. No visible mesh or
animation controller is created for a collision-only model. The Collision Models
example demonstrates node references, direct file sources and baked Points.

For editable point extraction, see [point colliders](pointColliders.md).

## Attachment constraints

Create Attachment3D children beneath each Body3D (or a descendant, including Bone3D).
Create a constraint node in the same world and set attachment0 and attachment1 to
those attachments. Their positions and orientations define the joint frames.
Available classes: BallSocketConstraint3D, HingeConstraint3D, SliderConstraint3D,
CylindricalConstraint3D, UniversalConstraint3D, RagdollConstraint3D, WeldConstraint3D,
GenericConstraint3D, RopeConstraint3D and SpringConstraint3D. PrismaticConstraint3D is the earlier
name of SliderConstraint3D and remains an identical class. Each family lives in its own module under
`nodes/physics/3d/constraintTypes/` (hinge, slider, spring, ...) and registers through
`constraintTypes/init.lua`; add a family by adding a module and listing it there. Constraint3D is the configurable base. The inspector provides
reference pickers and applicable limits, motors and spring settings. Generic exposes
translation and rotation limits. Disabled or destroyed constraints remove their
native connection; attachment changes rebuild it. Rope/Spring use a radial impulse
solver and honor AllowCollision through their native connection.

The Animation & Physics Laboratory demonstrates all ten concrete constraints,
a bone-driven rope, an animated physical rig, rolling balls and an inclined ramp.
