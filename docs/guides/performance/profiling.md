# Profiling and budgets

Open Debug / F4 → CPU profiler / error journal; enable profiling, close the popup,
play, then reopen and Refresh observations. Samples show last, exponential average
and peak milliseconds. Clear removes samples and journal entries. The profiler is
also a Workspace settings target. It is disabled by default.

Observed stages: scene update, Input, node/gameplay/physics update, existing model
node animation, audio update, screen UI, render preparation, light selection, main
submission, shadow map construction and physics solver. Nested stages overlap and
must not be added together. These are CPU wall-clock/submission measurements,
not isolated GPU durations. Memory is sampled once every 30 profiled rendered
frames: Lua KiB and graphics texture bytes. GPU resources outside textures and
native physics memory are not a complete process-memory measurement.

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
