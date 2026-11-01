# Mesh skin limits

Each `Mesh3D` owns its skin quality settings. Bones keep their animation and
hierarchy; these settings control how mesh vertices use that skeleton.

| Property | Range / default | Behavior |
| --- | --- | --- |
| `MaxBoneInfluences` | Integer 1–8 / 8 | Keep the strongest N imported weights per vertex and normalize their sum. |
| `BonePaletteLimit` | Integer 1–32 / 32 | Requested number of distinct bones in each GPU draw. Smaller palettes split triangles into more draw pieces. |
| `effectiveBonePaletteLimit` | Read-only | Largest palette used after accounting for indivisible triangles. |
| `skinDrawCount` | Read-only | Draw pieces generated for this authored mesh. |

The usual lower-camel-case names (`maxBoneInfluences`, `bonePaletteLimit`) and
PascalCase aliases work in Lua. Workspace exposes the same editable limits and
read-only diagnostics. Invalid fractions or values outside the range are rejected.

```lua
-- All skinned parts in one model instance:
Models.instantiate(world, model, {
    name = 'Character',
    maxBoneInfluences = 2,
    bonePaletteLimit = 16,
})

-- Or edit an individual mounted mesh, including at runtime:
mesh.MaxBoneInfluences = 1
mesh.BonePaletteLimit = 8
```

Limits are applied before frame-cache inspection on the next renderer draw.
Geometry is rebuilt only when a limit changes. The imported model and other
instances remain intact. Restoring 8/32 restores the exact original geometry;
raising an influence limit cannot invent weights absent from the source model.
Static meshes have no skin to reduce.

For intentionally rigid or rough bending, try 1 or 2 influences. This changes
deformation rather than delaying the animation clock. A smaller palette preserves
the deformation and usually increases draw calls; it is not an animation quality
slider. No bones are removed from the skeleton or silently replaced by another
bone. The GPU capacity remains 32 bones per draw.

A triangle cannot be divided between draw calls without changing its topology.
If it needs more bones than the requested palette limit, the effective limit is
raised to the largest triangle's joint count. Check `effectiveBonePaletteLimit`
to see that floor. Every original triangle and every retained weight survives.

Generated `Palette` children are internal draw pieces under the authored mesh.
They follow its transform, visibility, size, color and material components in
the main pass, shadows, depth prepass and wireframe. Edit limits on their parent.
Replacing a variant destroys its generated nodes and releases its GPU meshes.

Changed caster poses and light projections refresh affected shadow maps without
waiting for `Shadows.updateHz`. Stable maps remain cached; face budgets still
bound updates across multiple lights. Resolution, bias, normal bias and filter
settings retain their existing meaning. This prevents an old character pose in
the depth map from self-shadowing the current color-pass pose.
