# Profiling and budgets

Open Debug / F4 → CPU profiler / error journal. The profiler is disabled by default and
costs nothing while off.

## Panel

- **Profiler ON/OFF**, **Record session / Stop recording** (captures every frame, up to twenty
  minutes), **Export JSON / CSV** (writes `logs/profile-<utc>.json|csv` in the save directory),
  **Clear**, **Refresh**.
- Frame summary over the last ten seconds: mean frame time and FPS, p95, p99, worst frame,
  1% low FPS and the number of spikes (frames slower than twice the median). A bar chart shows
  the latest frames (red above the 60 Hz budget).
- Stage list sorted by mean time with p95, peak and share of the frame. Nested stages overlap,
  so shares can add up to more than 100%.
- Memory is sampled every 30 profiled frames: Lua KiB and texture bytes.

`--profile` on the command line records the whole session and saves both formats on quit.

## Measuring your own code

```lua
local profiler = manager.profiler            -- scene.manager.profiler inside a scene
local stamp = profiler:begin()               -- nil while disabled
-- ... work ...
profiler:finish('Bot AI', stamp)
local path = profiler:scope('Pathfinding', function() return grid:findPath(...) end)
```

Named tasks can span many frames and nest. `end` is a Lua keyword, so the call is `stop`:

```lua
katsa.profiler.start('generating map')     -- plain functions, no `self`
-- ... across frames ...
katsa.profiler.stop('generating map')      -- returns the elapsed milliseconds
```

A running task shows as `RUNNING <name> <seconds>` in the panel; each `stop` adds one sample under
that name, so the task appears among the other stages with mean, p95, peak and its place in the
exports. While the profiler is disabled both calls do nothing; `stop` without `start` logs one
warning per name.

Stage names are free text; each appears in the panel and as a column in the exports.
`profiler:summary()` returns `{ frame = {...}, stages = {...} }` for scripts and tests.

## Export format

CSV: one line per frame, columns `frame,time_s,frame_ms,lua_kib` followed by one column per
stage in milliseconds. JSON: `schema`, `app_version`, `scene`, `started_utc`, `columns`,
`summary` and `rows` (arrays in column order).

## Built-in stages

Scene update, Input, node/gameplay/physics update, model node animation, audio update, screen
UI, render preparation, light selection, main submission, shadow map construction, particles
and the physics solver. These are CPU wall-clock/submission measurements, not isolated GPU
durations.

Existing shadow statistics show faces/maps built, pending work/age, passes and depth
atlas bytes. The explicit shadow sampling A/B probe blocks on GPU readback and
includes the transfer cost; never run it every frame. It restores its renderer flags.

Workspace → Lighting / Render exposes:

- Render: renderDensity, MSAA, maxRenderPixels/maxRenderBytes, maxMeshDistance.
- Light settings: maxActiveLights (0..32), selection/update rates and cullInvisible.
- Shadows: resolution, distance, update rate and maximum faces updated per frame.
- Mesh: maxDistance, 0 disables its additional camera-distance limit.

Reducing resolution/light count changes quality, so v55 does not silently change the
Combined defaults. Try renderDensity=0.75 or maxActiveLights=16 as explicit device
quality choices, then measure on the phone. Retained static transform and instancing
caches preserve batching without changing transparent ordering. Geometry bounds use
transformed conservative spheres; skeleton-deformed bounds await skeleton support.

The journal is bounded to 64 entries; NodeTree, resource loading and scene failures
supply context where available. It records errors without suppressing failures.
Bone/particle visualization and animation/particle budgets are future system work.

## Where to find it, and loading phases

* In a running scene: **Debug / F4 → CPU profiler / error journal** (the same panel is in the
  editor workspace as *CPU profiler*). Switch **Profiler ON**, optionally **Record session**, and
  use **Export JSON / CSV** to write the report.
* From the command line: `--profile` records the whole run, including loading, and saves
  `logs/profile-*.json|csv` in the save directory on quit.
* **Load phases** are measured even while the profiler is off (a scene loads before you can switch
  it on). The panel lists them under *Loading <scene>* and recordings carry them as a `loading`
  object in the JSON export (`scene`, `total_ms`, `phases[{name, ms}]`). Built-in phases: open
  package / resources / audio, world / renderer / UI, node types and plugins, scene create script.
* Add your own phases in a scene script:

```lua
local profiler = scene.manager.profiler
profiler:beginLoad('My scene')                    -- optional: starts a fresh list
loadTerrain();  profiler:markLoad('Terrain')      -- time since the previous mark
buildNavMap();  profiler:markLoad('NavMap3D bake')
```

* Scopes with a name of your choice work anywhere, across frames, nested:

```lua
katsa.profiler.start('Loading scene')
-- ... many frames of async work ...
katsa.profiler.stop('Loading scene')              -- adds a sample; shows in stages and exports
local pathMs = katsa.profiler.scope('Bot plan', function() return map:findPath(a, b) end)
```
