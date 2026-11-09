# Post-processing

Post-processing follows Godot's Environment: each effect is its own section of the 3D
`Environment` with an `enabled` switch. Every effect is off by default, so a scene looks the
same until it opts in. In the Workspace the sections are the rows `Glow`, `SSAO`,
`DepthOfField` and `Adjustments` below `Environment`; screen-space anti-aliasing is
`screenSpaceAA` in `Rendering`. Volumetric fog is a mode of the scene `Fog` (below).

```lua
local e = scene.world.environment
e.glow.enabled = true
e.ssao.enabled, e.ssao.radius = true, 12      -- radius in world units
e.depthOfField.enabled, e.depthOfField.farDistance = true, 600
e.adjustments.enabled, e.adjustments.saturation = true, 1.2
e.fog.enabled, e.fog.volumetric = true, true  -- ray-marched fog with light shafts
e.render.screenSpaceAA = 'FXAA'
```

Chain order: scene, SSAO, volumetric fog, depth of field, glow + adjustments, FXAA. The user
interface is drawn after the chain, so it is never blurred or darkened. Only the enabled
passes run.

| Section | Properties |
| --- | --- |
| `glow` | `intensity` 0.8, `strength` 1, `mix` 0.05, `bloom` 0, `blendMode` (Additive, Screen, Softlight, Replace, Mix), `hdrThreshold` 0.8, `hdrScale` 2, `levels` 5 |
| `ssao` | `quality` (Low 8, Medium 12, High 20 samples), `radius` 1, `intensity` 2, `power` 1.5 |
| `depthOfField` | `farEnabled`, `farDistance`, `farTransition`, `nearEnabled`, `nearDistance`, `nearTransition`, `amount` 0.1, `quality` (Low 8, Medium 16, High 32 samples) |
| `adjustments` | `brightness`, `contrast`, `saturation`, `colorCorrection` (lookup-table image), `colorCorrectionStrength` |
| `fog` | Plain fog: `enabled`, `color`, `density`, `mode`, `offset`, `endDistance`, `maxOpacity`. Volumetric mode: `volumetric` (replaces the plain blend), `quality` (Low 16 steps / Medium 32 steps, both half resolution; High 48 steps at full resolution), `volumetricDistance` 120, `heightFalloff`, `baseHeight`, `anisotropy` 0.6, `lightEnergy` 1, `lightClearing` 0.5 (point and spot lights thin the fog they shine through), `ambient` 0.3, `shadows`, `skyAffect` |
| `render.screenSpaceAA` | `Disabled` or `FXAA` (works together with MSAA) |

## Differences from Godot

- The scene is rendered at 8 bits and tone mapped inside the material shaders, so the glow
  threshold (`hdrThreshold`) is measured after tone mapping, in 0..1. Godot measures it in HDR.
- Colour correction takes a lookup-table strip of N slices, N*N wide and N tall (for example
  256x16), not a 3D texture.
- SSAO and depth of field read the depth of the batched opaque scene; transparent surfaces and
  alpha cutouts are not part of it. SSAO is applied to the finished image rather than only to
  ambient light.
- There is no TAA (it needs per-pixel motion vectors and a history buffer). A vignette is not
  built in: put an `ImageRect` with a radial gradient over the screen.
- Volumetric fog is a screen-space ray march, not Godot's froxel grid. It is lit by the sun (with
  its cascaded shadows, which gives light shafts), by every point and spot light (halos and
  cones; their shadow maps count on High quality only) and by an ambient term. Light seen
  through the fog follows a Henyey-Greenstein phase (`anisotropy`).

## Quality profiles

`Environment:applyQualityProfile('Low' | 'Medium' | 'High')` also sets the SSAO and
depth-of-field quality and the number of glow levels; no effect is turned off.

## Cost and caching

A frame the renderer reuses (nothing moved) still runs the enabled passes; changing any
post-processing setting forces the scene itself to be redrawn once, because the depth and the
chain depend on the settings. SSAO needs a depth-only draw of the opaque geometry unless the
early depth pass already ran.

Tests: `--test-v108.7.post` (`v108_7/postProcessing.lua`). The reference scene is
`graphicsLab` ("Maximum graphics"), which has a switch per effect.
