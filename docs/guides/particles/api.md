# ParticleEmitter3D

```lua
local support = world:create('Attachment3D', { name = 'Exhaust', position = { 0, 8, 0 } }, vehicle)
local smoke = world:create('ParticleEmitter3D', {
    name = 'Smoke',
    rate = 30,
    lifetime = { 2, 4 },
    speed = { 4, 10 },
    direction = { 0, 1, 0 },
    spread = 25,
    gravityScale = 0,
    acceleration = { 0, 2, 0 },
    drag = 0.5,
    startSize = { 5, 10 },
    sizeCurve = { 1, 2, 3 },
    transparencyCurve = { 0.2, 0.5, 1 },
    startColor = { 0.5, 0.5, 0.5 },
    midColor = { 0.4, 0.4, 0.4 },
    endColor = { 0.2, 0.2, 0.2 },
}, support)
smoke:emit(40) -- Returns the accepted burst count after budgets.
smoke.enabled = false -- Stops automatic births; Drain is the default.
smoke:clear() -- Removes all live particles, retaining their pool.
```

Parents must satisfy the existing Node3D tree rules. Attachment3D is supported;
Bone3D attachments are supported. There is no per-particle
node or physics body. Signals and cleanup remain the existing node lifecycle:
connect('propertyChanged', ...), destroying, etc. The emitter's numeric emit(count)
overlaps the existing signal method; string emit(event, ...) still forwards to signals.

## Birth and shape

| Property | Meaning / units |
| --- | --- |
| rate | Births/second, capped by explicit live-particle budgets |
| lifetime | {minimum, maximum} seconds, sampled at birth; minimum > 0 |
| speed | {minimum, maximum} local units/second, sampled at birth |
| direction / spread | Local direction and cone half-angle in degrees, 0..180 |
| shape | Point, Box, Sphere, Disc or Cylinder |
| shapeSize | Full local X/Y/Z extents; Disc uses XZ, Cylinder uses Y height |
| surfaceOnly | Box faces, ellipsoid shell, disc perimeter, cylinder lateral surface |
| simulationSpace | World or Local; captured per particle at birth |
| startSize | Random minimum/maximum full quad size, world units before sizeCurve |
| startRotation / angularSpeed | Random min/max degrees and degrees/second |
| seed / setSeed(seed) | Scene-local deterministic RNG; no shared gameplay RNG mutation |

Box volume samples are uniform; Box faces use equal face choice, not area weighting.
Sphere/Disc/Cylinder sample their normalized primitive then scale to shapeSize, so a
nonuniform ellipsoid's surface sampling is not uniform by final surface area.
World births transform position/velocity once and stay behind when the support moves.
Local particles continue to follow support movement/rotation/scale. Changing space
only affects later births. Birth speed/shape inherit emitter scale; quad size remains
world-sized. Live colors, curves, forces and appearance settings affect existing particles.

## Forces and attraction

Acceleration is authored in world units/second squared. With useWorldGravity=true,
gravity uses Physics.gravity when available, otherwise the emitter gravity vector.
Disable useWorldGravity to author an independent gravity field. gravityScale is a
multiplier: 0 disables gravity, 1 uses full gravity, negative values reverse it.
The default gravity is {0,-196.2,0} world units/second squared.

World.particles.wind is a world-space velocity; windInfluence scales it. drag is a
per-second coefficient for exponential velocity relaxation toward wind. With drag=0
there is no aerodynamic wind coupling. acceleration and gravity still apply.

attractionEnabled adds acceleration toward the fixed world-space attractionPoint.
For distance d <= attractionRange, magnitude is:
`attractionStrength / (1 + (d / attractionSoftening)^2)`.
Outside range it is zero; softening must be positive. Strength is acceleration, not
Newtons: particles have no mass/body. The zero-distance case safely adds no direction.
This model is a controllable visual force, not gravitational N-body simulation.

## Appearance and rendering

startColor / midColor / endColor are RGB 0..1; transparencyCurve and sizeCurve each
contain values at normalized ages {0, .5, 1}. Segments use linear interpolation.
Transparency multiplies sprite alpha; sizeCurve multiplies sampled startSize.
Texture points to a supported image resource. Pixel uses existing independent filter
variants, so changing one emitter does not change other users of the image.

atlasEnabled uses atlasGrid {columns, rows}, row-major frames from the top left,
atlasFPS frames/second and atlasLoop (otherwise clamps to the last frame). Texture
cells have equal dimensions. Transparent gutters are recommended to prevent filtering
bleed. The example includes a small procedural 4x4 atlas.

orientation=Camera faces the camera. Velocity aligns the quad up axis with velocity,
using a camera-facing plane and a stable fallback for zero/parallel velocity.
Axes uses emitter-local axisRight/axisUp transformed to the world and orthogonalized.
Initial rotation/angular speed rotate within that plane.

Alpha, Add and Multiply use depth testing without depth writes; particles behind
opaque geometry are hidden. Multiply outputs white for fully transparent pixels.
Particles sort back-to-front within an emitter. Emitters join the engine transparency
queue by emitter-origin depth alongside meshes/world UI. Intersecting emitters or
large transparent meshes can therefore still have ordering artifacts; this is not
order-independent transparency or a global per-triangle/per-particle sort. Particles
support lighting and optional shadows in v70; see [particle rendering](../rendering/particlesShadows.md). Soft depth intersections/distortion are future effects.

## Collision, budgets and lifetime

collisionEnabled performs optional point-segment raycasts against existing physics
bodies. Triggers and non-collidable bodies are excluded. Bounce uses restitution and
collisionFriction; Kill ends lifetime. This is not a spherical particle collider or a
rigid-body solver, and budget-skipped particles can pass through a surface.

The shared system defaults: maxParticles=4096, collisionBudget=64 raycasts per update,
fixedDelta=1/60, maxSteps=4. A large delta discards excess catch-up time rather than
creating unbounded work; no phone performance promise follows from these defaults.
Emitter rate controls birth frequency directly. maxParticles on the emitter and
system cap live counts. collisionBudget caps shared raycasts; maxSteps caps simulation
catch-up work. These budgets are editable under Workspace Particle budgets. Burst requests
return the accepted count; rejected births increment stats.dropped. Lowering a budget
does not pop existing particles: births wait while old particles drain. Simulation
is controlled by offscreenBehavior: Pause (default) or Simulate. See [visibility](visibility.md).

World.particles.stats reports live particles, dropped births, collision queries,
steps, CPU update/submission milliseconds, drawn particles, draw calls and approximate
allocated mesh bytes (updated on preparation; excludes driver overhead, textures and
Lua pools). Each visible emitter uses one dynamic mesh draw. Records, vertices and
buffers are reused after warm-up; there is no promise of zero temporary Lua allocation.
Validation is cached until authored settings change, including in-place vector edits.
Emitter order and particle collision cursors rotate to distribute the shared budget.

Enabled=false stops automatic emission. Drain lets existing particles expire;
Clear removes them. Explicit emit(count) remains a valid burst while disabled, but
Clear policy removes it at the next simulation step. A disabled ancestor also stops
automatic births. Visible=false hides particles and automatic births. Destroying the
emitter or its parent immediately removes all particles, unregisters it and releases
its mesh. Scene teardown releases textures/shaders through the existing resource scope.

The Particle Laboratory includes compact collapsible controls and direct Workspace
inspection. Every setting is described by the shared property schema; conditional
settings preserve their values when hidden. Numeric range/curve fields show Min/Max
or Start/50%/End labels. Invalid edited settings are rejected with previous values retained.

The renderer uses LÖVE 11.5 dynamic Mesh APIs:
[Mesh:setVertices](https://love2d.org/wiki/Mesh:setVertices) and
[Mesh:setDrawRange](https://love2d.org/wiki/Mesh:setDrawRange).
