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

The group looks at the world's current camera once per update.

## From a model file

Name the objects in Blender (or any tool) `Tree`, `Tree-lod1`, `Tree-lod2` and `Models.instantiate` /
`world:loadModel` builds a `LODGroup` called `TreeLOD` for you, in the place of the most detailed node.
Matching ignores letter case and Blender's `.001` copy suffix; `-lod0` also names level 0. The levels
need the same parent. `settings.lod` holds the group's properties, `lod = false` turns it off:

```lua
world:loadModel('assets/models/forest.glb', {
    lod = { mode = 'ScreenSize', screenSizes = '0.25, 0.08', bias = 1.5 },
})
```

The created groups are listed in `model.lodGroups`. The importer is `source/engine/import/autoLod.lua`;
the choice of the level is plain functions in `components/rendering/lodSelect.lua`.

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
- Per-group settings by name for imported models (one `settings.lod` applies to all groups of a model).
