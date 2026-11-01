[Current colliders and constraints](collidersConstraints.md) and [backend adapters](backends.md) describe the physics API.

# Hierarchy, UI and physics

Folder is organizational. Node3D, Mesh3D, Camera3D, Attachment3D, World3D and BillboardUI are spatial classes. Transform inheritance passes through folders. Attachment3D can inherit rotation while excluding a visual parent's scale. Camera3D selection and visibility-layer masks are World3D-owned.

ScreenUI is a UI service root containing CanvasGroup nodes. Widgets must explicitly name a parent with a CanvasGroup or BillboardUI ancestor belonging to the same UI service. BillboardUI widgets are direct children of the BillboardUI, with no duplicate ScreenUI subtree. Frame, TextLabel, Button, ImageLabel, Slider, ScrollFrame and UICorner remain available.

CanvasGroup stores zIndex, transparency, enabled and visible. zIndex sorts siblings consistently for drawing and picking. Partial group transparency renders the subtree to an intermediate canvas and applies opacity once to the composition; overlapping children do not become cumulatively brighter. Disabled, hidden or fully transparent groups block descendant interaction. Text/UI font density follows display scale.

The OimoPhysics backend supports rigid-body collision, box/sphere/capsule shapes, convex and detailed model colliders, raycasts, impulses, damping, friction, restitution and joints. Physics bodies may sit below organizational Folder nodes under World3D; transformed spatial parents are rejected for rigid bodies. Physics coordinates are World3D space with configurable unitsPerMeter.

Body:teleport updates the solver pose and visual state. Collider3D changes require body rebuilding. Capsule character movement supports acceleration, air control, ground probes, slope limits, coyote time and jump buffering. See examples/labs and tests/nodesPhysics.lua for working code.

Attachment3D remains a named socket specialization of Node3D: inheritScale defaults to false, so an enlarged visual mesh does not enlarge the head/tool offsets. Camera3D, lights and BillboardUI inherit its local translation/rotation. BillboardUI size is UI width/height, not spatial scale. Legacy attachment/adornee options are resolved to hierarchy parents at construction. Reparenting updates the inherited transform immediately.

UI visible controls drawing; enabled controls interaction. Disabling a CanvasGroup does not hide its subtree. Captured pointers are cancelled when their ancestor becomes disabled, invisible or fully transparent. Use visible for show/hide. Debug callbacks read the current camera each draw; DebugControls sits above the capturing DebugMenu.

## v44 lifecycle

All World3D-owned nodes retain scene identity across detach. `docs/nodeLifecycle.md` specifies queries, tags, processing and destruction ordering. Body insertion/removal inside contact callbacks is queued until the solver step completes; hierarchy destruction is immediate. Other physical edits still use the documented API restrictions.

## v45 spatial poses

Mesh3D.size controls only geometry dimensions. Node3D.scale controls the hierarchy;
Attachment3D excludes spatial scale by default and can opt in. Body creation supports
positive uniform scale, applied to colliders once. Live body dimensions/scale require
a rebuild. See `spatialTransforms.md` for world/local APIs, units, shear constraints,
keep-world reparent and migration.
