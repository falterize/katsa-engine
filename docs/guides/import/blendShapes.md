# Blend shapes (Blender Shape Keys)

glTF morph targets import as blend shapes. Blender writes its **Shape Keys** as morph targets when
you export glTF 2.0 (`.glb`) with *Shape Keys* enabled; sparse accessors (the exporter's default
for shape keys) are supported.

## API

The names follow Godot's `MeshInstance3D`. Indices are **1-based** (Lua); a shape can be given by
name or by index.

```lua
local objects = Models.instantiate(world, model, { name = 'Face' })
local face = objects[1]

face:getBlendShapeCount()              -- number of shapes, 0 for a mesh without any
face:findBlendShapeByName('Smile')     -- 1-based index, or nil
face:getBlendShapeName(1)              -- 'Smile'
face:getBlendShapes()                  -- { [1] = 'Smile', [2] = 'Wide' } (a fresh table)
face:setBlendShapeValue('Smile', 0.7)  -- weight, usually 0..1 (values outside extrapolate)
face:getBlendShapeValue('Smile')
```

An unknown shape in `setBlendShapeValue` is an error. Imported default weights (`mesh.weights`)
are applied on instantiation. Shape names come from `mesh.extras.targetNames`, which the Blender
exporter writes; other files get `Shape1`, `Shape2` ...

All draws of one glTF mesh (a skinned mesh may be split into several) share the same weights, so
setting a value on any of its `Mesh3D` objects updates them all.

## Animation

A glTF animation channel with path `weights` drives the shapes through the `Animator` exactly like
bone channels: tracks blend by weight and bone mask. A shape that no active track animates keeps the
value set from code, so scripts and clips can control different shapes of the same mesh.

## How it works

- Every `Mesh3D` with shapes owns a private **dynamic** copy of its vertices; the imported asset
  stays untouched and can be instantiated again.
- Setting values only marks the mesh dirty. Vertices are rebuilt **once per frame**, after the node
  update, however many shapes changed. Positions and (when the target has them) normals are
  morphed; the cull radius follows the morphed extent.
- Cost is proportional to `vertices x active shapes` on the CPU plus one vertex upload per changed
  mesh per frame; shapes with weight 0 are skipped.

## Inspector

Select a mesh with shapes in the Workspace: every shape appears as a number row `blend: <name>`
under the other properties; editing it sets the weight for all draws of that glTF mesh.

## Skin limits

`maxBoneInfluences` / `bonePaletteLimit` may split a skinned mesh into several palette draws. The
new draws are re-sliced from the original shape data (`BlendShapes.resplit`), so the shapes keep
following the weights after a split and when the limits are relaxed again.

## Limits

- Tangent deltas are ignored (the engine has no normal maps on imported meshes).
