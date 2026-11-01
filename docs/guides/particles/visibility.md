# Particle visibility and material composition — v69

## ParticleEmitter3D.OffscreenBehavior

- Pause (default): if neither the emitting source nor its existing particles can
  affect the active camera view, freeze ages, movement and automatic births and
  skip collision queries. Resume from that state when relevant again. This is
  a visual-effect optimization, not background gameplay simulation.
- Simulate: preserve continuous time, births, movement and collision queries
  offscreen. Use this when effects must continue interacting with the world.

Visibility uses camera layers, drawDistance, near/far, frustum, emitter maxDistance,
ancestor visibility/opacity and existing world-space particles. A source outside
the view does not freeze particles still inside it. These are conservative CPU
visibility checks, not GPU occlusion queries: hiding behind a wall does not pause
an effect. Explicit emit(count) still queues a bounded burst while paused.

When a Pause emitter is active because its source or some particles are visible,
other particles can still move and age, but collision queries are omitted when
both segment endpoints are outside the view. Those omitted segments are not
replayed on reentry. Simulate retains collisions on those paths. Ordinary budget
deferral on visible particles still retains the untested sweep.

The renderer skips irrelevant emitters before binding shaders and updating GPU
vertex buffers. draws=0 means no particle draw submission; rays and simulation
are separate counters. stats.pausedEmitters counts paused emitters.

```lua
emitter.offscreenBehavior = 'Pause'
emitter.offscreenBehavior = 'Simulate'
```

## SurfaceAppearance3D composition

katsa's additive blend mode does not accumulate destination alpha. The previous
composition produced RGB colors with zero alpha, making intermediate appearances
invisible. v69 adds full RGBA explicitly in alternating render targets with Replace
blending. Texture alpha, material weights and opaque mode are preserved.

Transparency=1 and Enabled=false contributions load no maps and do no composition
draws. A mesh with no contributing appearances uses its solid Color and releases
blend buffers. A hidden/fully transparent parent mesh also skips composition and
releases buffers. Returning to a blend rebuilds its buffers on demand. Unused data
map buffers are released when their channel is no longer required. Shared source
textures remain in the scene resource cache for reuse.

One scratch RGBA canvas is reused across channels. Maximum blend-buffer storage at
256 pixels and RGBA16F is about 3.5 MiB for six maps plus scratch, excluding source
textures. Stable blends do not submit new composition draws. Basic visibility/list
checks still run; invisible components are not literally zero CPU cost.
