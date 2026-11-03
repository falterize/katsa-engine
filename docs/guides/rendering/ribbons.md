# Beam3D and Trail3D

Two ribbon effects in `source/engine/nodes/effects`, both drawn by `source/engine/ribbons`:

- **Beam3D** is a textured ribbon between two nodes (Roblox `Beam`). The centre line is a cubic Bezier.
- **Trail3D** is a ribbon that follows a moving node and keeps its history (Roblox `Trail`).

Both are ordinary nodes with inspector properties, live under `Effects`, and draw as one stream mesh per
node through the particle sprite shader, so they share lighting, shadows, shader layers and layer groups
with particles. There is a demo scene, `ribbonLab`.

## The two ends: any Node3D

`attachment0` / `attachment1` accept **any Node3D** (an `Attachment3D` works too). A model therefore needs no
extra attachment: use one of its bones or meshes. `curveSize` uses the node's X axis, a flat strip uses its Y
axis as the face normal.

## Beam3D

| Property | Meaning |
| --- | --- |
| `attachment0`, `attachment1` | Start and end node. Nothing is drawn while one is missing. |
| `width0`, `width1` | Width at each end. |
| `curveSize0`, `curveSize1` | Bezier control point distance along each node's X axis. 0 gives a straight beam. |
| `segments` | Straight pieces of the curve (1-128). The `Low` / `Medium` quality profiles scale it by 0.5 / 0.75. |

## Trail3D

`trailMode` selects how the width is defined:

- **Single**: one node (`attachment0`, or the Trail3D itself when it is empty) is the centre. The trail always
  turns its width toward the camera; `width` sets the width. Put a Trail3D under the object and it works.
- **Dual**: `attachment0` and `attachment1` mark the top and bottom edge. Their distance is the width and
  `faceCamera` chooses between a camera facing ribbon and a flat one that keeps the nodes' orientation.

| Property | Meaning |
| --- | --- |
| `lifetime` | Seconds a point lives. |
| `minLength` | Distance the node must move before a point is stored. |
| `maxLength` | Longest kept path behind the head (0 = unlimited). |
| `maxPoints` | Hard cap on stored points (2-1024). |
| `breakDistance` | A jump longer than this clears the trail (teleport). 0 disables. |
| `width` | Single mode width. |

`Trail3D:clear()` removes all points. Points are sampled from the interpolated render pose once per rendered
frame and aged with the world's simulation time, so `timeScale` and pause apply.

## Shared appearance

- **Image**: `texture` is a normal image path (`scene://assets/textures/trail.png`, `shared://...`);
  `imageMode` is `Decal` (static), `Texture`, `Tiles`, `Atlas` or `XML`, with `pixelate`, `tileSize`,
  `tileOffset`, `textureSize`, `atlasGrid`, `atlasFrame`, `atlasEnabled`/`atlasFPS`/`atlasLoop` and `xml` -
  the same configuration as every other image node. A missing file shows the diagnostic checker.
- **Texture mapping** (`Decal` mode): `textureMode` is `Stretch` (once over the ribbon), `Wrap` (repeats every
  `textureLength` units and moves with the ribbon) or `Static` (repeats in world space). `textureSpeed`
  scrolls along the ribbon in repeats per second. The other image modes use their own mapping.
- **Ramp**: the child `RibbonRamp` node holds the `color`, `transparency` and `width` curves over the ribbon
  coordinate (Beam: 0 at `attachment0` to 1 at `attachment1`; Trail: age of the point divided by `lifetime`).
  `color` multiplies it, Node3D `transparency` fades the whole ribbon.
- **Light**: `lightEmission` 0..1 blends from normal alpha to additive glow; `lightInfluence` 0..1 (default 0)
  blends from unlit to fully lit; `brightness` scales the result. `zOffset` shifts the transparency sort.
- **Shadows**: the same four options as particles, from one shared component
  (`components/shadowing.lua`): `castShadow`, `receiveShadow`, `shadowGroup` and `shadowAlphaCutoff`.
  `castShadow` writes the ribbon into the shadow maps as an alpha tested strip, `receiveShadow` darkens it
  with shadows (it only shows when `lightInfluence` is above 0). `shadowAlphaCutoff` is a shadow-pass-only
  threshold: texels more transparent than it cast no shadow. It is not Mesh3D `alphaCutoff`, which is a
  material mode that also changes how the mesh is drawn. `ParticleEmitter3D` adds `shadowMaxParticles`.
  Both producers share `graphics/shadows/casterProxy.lua`.
- **Layers**: `layerGroup` works like any Node3D; shader layers apply through `Shader3D` nodes exactly as for
  particles; `maxDistance` culls far ribbons.

## Code layout

`ribbons/geometry.lua` (pure strip and Bezier builder), `source.lua` (Beam curve and Trail history),
`lifetime.lua` (ramp), `renderer.lua`, `shadows.lua`, `system.lua` (per-world registry, `world.ribbons`).
`nodes/effects/ribbon.lua` holds the shared properties; `beam3D.lua` and `trail3D.lua` add their own.

Known limits: ribbon lighting uses the camera-facing normal, like particles; shadows are cast by the strip
geometry at the current frame, so very thin ribbons give thin shadows; `Wrap` and `Static` need `Decal` mode.
