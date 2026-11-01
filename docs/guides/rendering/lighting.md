# Katsa v83 — Shared directional lights and physics debug

Run the project with `katsa .` or a packaged `.katsa` archive.
Code, examples, assets and documentation are included.

## Unified Debug hierarchy

Workspace exposes:

- `World3D > Environment > debug > gizmos`
- `World3D > Environment > debug > physics`
- `bones` and `wireframe` on the common `debug` settings row.

Physics settings include enabled, wireframe, drawShapes, drawAabbs, drawBases,
drawContacts, drawContactBases, drawPairs, drawJoints, drawJointLimits and drawBvh.
Physics debug is now drawn inside the world's render canvas, including a world
rendered through ViewportFrame. Enabling debug does not pause or enable simulation.
The old `world.physics.debugEnabled` API shares the canonical enabled setting.
Each World3D owns its settings; its physics backend binds when assigned to that world.

## DirectionalLight3D replaces Environment.sun

There is no Sun settings group, fallback sunlight or environment Sun control.
Create explicit DirectionalLight3D nodes, each with its own Enabled, Rotation,
Color, Brightness, CastShadow, ShadowGroup and Priority. The creation alias
`DirectionalLight` remains available.

```lua
local key = world:create('DirectionalLight3D', {
    name = 'KeyLight',
    rotation = { 65, 45, 0 },
    color = { 255, 238, 210 },
    brightness = 1.2,
    castShadow = true,
})
local fill = world:create('DirectionalLight3D', {
    name = 'FillLight',
    rotation = { 50, -50, 0 },
    color = { 150, 180, 255 },
    brightness = 0.4,
    castShadow = true,
})
world.environment.shadows.enabled = true
```

Direction is derived from the transformed **local +Z axis**. Rotation.X = 90
with zero Y/Z rotation points rays down world Y. Parent rotation also applies.
Position does not affect illumination or the directional shadow projections.
There is no editable direction property. Old `direction` creation input is
converted to Rotation once and discarded; editing direction afterwards is
unsupported. The orientation helper is for imported direction vectors, not a
second runtime orientation control.

Disable or destroy all directional nodes to remove directional illumination.
PointLight3D/SpotLight3D lighting and shadows remain independent. Environment
Ambient, Brightness, tone mapping and exposure keep their existing roles.

## Shared active-light limit

**Every active selected DirectionalLight3D occupies one slot** of
`Environment.lightSettings.maxActiveLights`, shared with Point and Spot.
The renderer supports 32 total selected sources. For a limit of 12, two selected
directional sources leave up to 10 slots for local sources.

Directionals are globally relevant and are selected before local sources.
If directional sources alone exceed the limit, higher Priority wins; equal
priority uses creation order. Remaining slots go to nearby relevant Point/Spot
sources with the existing selection hysteresis. Surviving sources retain their
GPU slot order. Directional rotation/color/brightness uploads are immediate;
selection membership still uses the existing selectionHz schedule.

Direct and Masked loops both support the same mixed selected set. Masked always
includes a selected directional source because it has no finite illumination
radius. Existing particle lighting remains capped at eight selected sources;
it now understands directional sources in those slots, including their shadows.

## Independent directional shadows

Every selected shadow-casting directional source has its own three nested,
texel-snapped cascades in the **shared shadow atlas**. Cascade extents are
shadow distance / 8, / 3 and / 1, with the existing transition blend. Point
sources use up to six faces; spots one. Shared resolution, bias, normalBias,
filtering, distance, updateHz and maxUpdateFaces apply to every source type.
A directional light costs one lighting slot but up to three shadow passes.
`updateHz` schedules maintenance scans; changed caster poses or light/cascade
projections bypass that deadline so the depth and color passes use current poses.
Unchanged maps stay cached, and `maxUpdateFaces` still bounds ordinary queues.

The former global-sun special case was removed from the world/particle shaders
and shadow scheduler. Projection math lives in shadowProjection.lua; directional
cascade generation lives in directionalShadows.lua and directionalCascades.lua.
They reuse the same queue, cache, batching, atlas and shader sampling pipeline.

Static directional sources/camera/casters reuse their maps. Rotating one source
invalidates its cascades; translating it does not. Camera movement updates the
snapped directional projections while valid unchanged local maps remain cached.
Caster edits use old and new bounds against each source's published volume.
Atlas residency preserves surviving sources. Cascade groups are atomic; a three
face source can exceed a smaller budget to guarantee forward progress. Atlas
recreation still rebuilds necessary maps coherently in one frame and may spike.

## Examples and validation

In **Shadows**, expand `World3D > Lights` for `DirectionalSun` and
`DirectionalFill`. Both start disabled. Their two separate controls allow both
to be enabled simultaneously. Other former-Sun examples now create real nodes;
the day/night example changes its DaySun Rotation, Enabled and Brightness.

`katsa path/to/project --test-v83` performs focused native checks. Validation
covers real pixel contributions and independent shadows, Rotation and parent
rotation, shared slots/priority, static reuse, mixed local/directional shadows,
Direct/Masked agreement, particles, physical lines in the world canvas, and the
existing local-cache integration checks. Migrated Shadows, Occlusion,
SurfaceGallery, ModelLab, Platformer, Viewports and NightPlayer examples render.
The source and packaged release each passed **53 checks** in LÖVE.
Historical measurements are retained with the external release reports.

The runtime is desktop LÖVE 11.5 with Mesa llvmpipe software OpenGL. These checks
are not Android/device FPS measurements. Multiple directional lights add both
pixel work and shadow passes; one slot does not mean a negligible GPU cost.
Historical version-specific test commands and guides describe their older API;
use `--test-v83` and this guide for the current directional-light API.
