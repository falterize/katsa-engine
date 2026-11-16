# Level of detail: LODGroup

`LODGroup` (`source/engine/nodes/spatial/lodGroup.lua`) is a `Node3D` that shows **one of its children at
a time**. The children are the levels, in order: the first is the most detailed (level 0), the next ones
are coarser. The group sets the `visible` of its children, so give it nothing else to show or hide. Hidden
levels are not drawn and do not cast shadows.

```lua
local tree = world:create('LODGroup', { name = 'Tree', mode = 'Distance', distances = { 25, 60, 150 } })
world:create('Mesh3D', { name = 'High', geometry = high }, tree)   -- level 0
world:create('Mesh3D', { name = 'Mid', geometry = mid }, tree)     -- level 1
world:create('Mesh3D', { name = 'Low', geometry = low }, tree)     -- level 2
```

Here level 1 starts at 25 world units from the camera, level 2 at 60, and the whole group is hidden
beyond 150. The last number is optional: without it nothing is hidden.

## Two modes

| `mode` | The thresholds are in `...` | Level `k + 1` starts when |
| --- | --- | --- |
| `Distance` (default) | `distances`, ascending world units | the camera is further than the k-th number |
| `ScreenSize` | `screenSizes`, descending fractions | the group covers less than the k-th fraction of the screen height |

`ScreenSize` follows how big the group *looks*, so a large building changes level further away than a
small rock and the result does not depend on the field of view or the resolution:

```lua
world:create('LODGroup', { mode = 'ScreenSize', screenSizes = '0.3, 0.1, 0.02' }) -- 30%, 10%, hidden below 2%
```

The lists are comma separated text in the inspector; in code a table (`{ 25, 60, 150 }`) works as well
and is converted.

## Defaults

An empty list, or a `0` entry, uses a default taken from the size of the group (`radius`; `0` measures the
bounding sphere of level 0 itself):

- `Distance`: the first switch at 6 radii from the camera, each next one 2.5 times further.
- `ScreenSize`: the first switch at 30% of the screen height, each next one at 40% of the previous.

Only the hide distance (one number past the last level) is never defaulted.

## Other properties

| Property | Default | Meaning |
| --- | --- | --- |
| `bias` | 1 | Above 1 lowers the detail sooner (weak devices), below 1 keeps it longer. One number moves every switch point |
| `hysteresis` | 0.1 | A finer level comes back only after passing its switch point by this fraction, so a group on the border does not flicker |
| `radius` | 0 | Size of the group for the defaults and for `ScreenSize`; 0 measures level 0 |
| `forceLevel` | -1 | Pins a level (0 = most detailed); -1 chooses by the camera |
| `level` | | Read-only: the level shown now, -1 when hidden (`group:getLevel()`) |
| `referenceFov` | 84 (the default lens) | `Distance` only: the lens the distances were set for (see below); 0 turns it off |
| `fadeTime` | 0 | Seconds the old and the new level cross-fade; 0 switches at once |
| `animationRates` | empty | `Animator.poseRate` per level, for example `60, 30, 10` |
| `shadowLevel` | -1 | The last level that casts shadows; -1 keeps every level as authored |
| `billboardImage` | empty | An image: adds a last, flat level that faces the camera (see below) |

The group looks at the world's current camera once per update.

## Weak devices: the quality profile

`Environment.render.lodBias` multiplies the `bias` of **every** group in the world. The quality profiles
set it (`Low` 1.5, `Medium` 1.2, `High` 1; `Environment:applyQualityProfile`), so a phone drops detail
sooner than a desktop without touching any scene. Nothing is removed: only the switch points move. Set it
by hand in the inspector (Environment, render) when a scene needs its own value.

## Zoom and field of view

In `Distance` mode a camera that zooms in (a smaller `fov`) makes things look closer, so the group keeps
the detail of a nearer camera: the distance is multiplied by `tan(fov / 2) / tan(referenceFov / 2)`.
`referenceFov` is the lens the numbers in `distances` were written for; its default is the default lens of
`Camera3D`, so an unzoomed camera changes nothing. Orthographic cameras ignore it. `ScreenSize` mode needs
none of this, because it measures what is actually on screen.

## Cheaper levels

- **Shadows.** `shadowLevel = 0` lets only level 0 cast shadows, `1` the first two levels, and so on; far
  levels then cost nothing in the shadow pass. The authored `castShadow` of each mesh is kept and comes
  back with `-1`.
- **Animation rate.** `animationRates = '60, 30, 10'` sets the `poseRate` of the model's `Animator` for the
  level shown (levels past the list use the last number), so a far character updates its bones less often.
  An empty text restores the authored rate. All levels of one character share one animator.

## Cross-fade

With `fadeTime > 0` the old level stays while the new one comes in: the meshes of both are drawn with
growing and fading `transparency` and the old one is hidden when the time is up. Without it the switch is
instant (the default). Both levels are drawn during the fade, and transparent meshes sort like any other
transparent mesh, so keep `fadeTime` short (0.2 to 0.5 s). A switch during a fade ends the running fade
at once. The authored `transparency` of the meshes is restored.

## Billboard level

For trees and bushes seen from far away, a picture is cheaper than any mesh. Set `billboardImage` to an
image with transparency and the group adds one more level at the end: a flat quad that turns around the
vertical axis to face the camera, drawn with the image (alpha mask).

```lua
world:create('LODGroup', {
    name = 'Pine',
    distances = '30, 80, 200',          -- three meshes, then the billboard from 200
    billboardImage = 'assets/textures/pine.png',
    billboardHeight = 12, billboardWidth = 6,
})
```

`billboardWidth` and `billboardHeight` are in world units (0 uses the group `radius`); `billboardPivot`
`Bottom` (default) puts the group position at the lower edge of the picture, `Center` in the middle. The
quad is a child called `<group name>Billboard`; clearing `billboardImage` removes it. It casts no shadow.

## From a model file

Name the objects in Blender (or any tool) `Tree-lod0`, `Tree-lod1`, `Tree-lod2` ... (the most detailed
first) and `Models.instantiate` / `world:loadModel` builds a `LODGroup` called `TreeLOD` for you, in the
place of the level 0 node. This is the recommended style: every level says what it is. A plain `Tree`
means level 0 as well, but a plain name next to `Tree-lod0` is an error that names both nodes. Matching
ignores letter case and Blender's `.001` copy suffix. The levels may have different parents: they move
into the group and keep their place in the world.

`settings.lod` holds the properties for every group of the model; `settings.lod.groups` overrides them
for one group by its name (the part before `-lodN`); `lod = false` turns grouping off:

```lua
world:loadModel('assets/models/forest.glb', {
    lod = {
        mode = 'ScreenSize', screenSizes = '0.25, 0.08', fadeTime = 0.3,   -- all groups
        groups = { Tree = { screenSizes = '0.2, 0.05', animationRates = '30, 10' } },
    },
})
```

### With collision (`-col`)

The collision suffixes of `autoCollision` (`-col`, `-colonly`) may stand before or after the LOD suffix:
`Tree-lod0-col` and `Tree-col-lod0` mean the same. Only the most detailed level has a collider. A `-col`
on a coarser level (`Tree-lod1-col`) is ignored with a warning in the resource journal. For a simpler
shape, add a hidden `Tree-colonly` mesh: it becomes the collider (attached to level 0) and is never a
level. A name without a LOD suffix is its own mesh, so `Tree` and `Tree-col` stay two separate meshes; to
make `Tree-col` the level 0 of a group, write `Tree-lod0-col`.

The created groups are listed in `model.lodGroups`. The importer is `source/engine/import/autoLod.lua`
(names are read by `import/modelNodes.lua`); the choice of the level is plain functions in
`components/rendering/lodSelect.lua`; fading, shadows and the billboard are `lodLevel.lua` and
`lodBillboard.lua` beside it.

## Characters and animation

The skeleton belongs to the model, not to a mesh. If every level of a character is a mesh on the **same
armature** (same bones, the same skin), the animation keeps playing when the level changes: only the
visible mesh differs. Give the coarse levels weights on the same bones (often fewer per vertex). A level
that carries a skeleton of its own would need its pose copied from the first one; do not build it that way.

`Mesh3D.maxBoneInfluences` and `bonePaletteLimit` (see `skinLimits.md`) are a cheaper kind of level of
detail for skinned meshes: they change how precisely a mesh follows the bones, not its triangle count.

Test model: `tools/import/makeLodDemo.py` writes `validation/tests/fixtures/models/lod.glb` (three static
levels and two skinned levels on one skeleton with a clip).

## What it does not do

- It does not make the coarse meshes: they come from your tool. Automatic mesh simplification is an open
  idea (`docs/TODO.md`).
- The animation of the bones is calculated whichever level is shown.
- Choose the level for several cameras at once (split screen); the world's current camera decides.
- Switch physics by distance; colliders stay as they are.
