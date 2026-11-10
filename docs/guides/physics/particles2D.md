# 2D and 3D particles

ParticleEmitter2D is a Node2D under a screen World2D, a spatial group, Body2D or
Collider2D. It uses Y-up world coordinates. Its optional adornee must be a Node2D
in the same World2D; ownership and destruction still follow Parent.

```lua
local emitter = scene.ui:create('ParticleEmitter2D', {
    name = 'Sparks', position = { 200, -300 },
    shape = 'Disc', shapeSize = { 30, 12 }, surfaceOnly = false,
    rate = 40, lifetime = { 1, 3 }, speed = { 80, 160 },
    direction = { 0, 1 }, spread = 35,
    startSize = { 6, 12 }, gravityScale = 0.4,
    collisionEnabled = true, collisionResponse = 'Bounce',
    restitution = 0.5, collisionFriction = 0.1,
    offscreenBehavior = 'Simulate',
}, scene.ui)
emitter:emit(20)
-- emitter:clear(); emitter:setSeed(123)
```

2D and 3D share emission budgets, particle pooling, deterministic seeds, fixed
steps, lifetime distributions, velocity integration, drag/wind, world or custom
gravity, attraction, Local/World spaces, rotation/angular velocity, disabled
Drain/Clear behavior, offscreen Pause/Simulate, lifetime Ramp bindings and bounded
physics sweeps with Bounce/Kill responses. Particles are points for collision;
neither dimension creates one rigid body per particle. LifetimeRamp exposes
size, transparency, color and rotation through the existing sequence editor.

2D shapes are Point, Box, Disc and Line; 3D retains Point, Box, Sphere, Disc and
Cylinder. Direction, shapeSize, acceleration, gravity, attractionPoint and axes
are Vector2 for 2D, Vector3 for 3D. Camera/Velocity/Axes orientations are supported.
2D uses Alpha/Add/Multiply batches, named layer groups and camera/distance culling.
Unlit/brightness are supported; lit 2D sprites use their World2D Environment ambient
light. Brightness is an `Adjustments` setting of the World2D Environment. 3D light sources, shadow casting and shadow reception remain 3D renderer
features; World2D does not contain a separate 2D lighting/shadow scene graph.

Every world has persistent particle settings at `world.environment.particles`,
including before its first emitter. Configure wind, maxParticles, collisionBudget,
fixedDelta and maxSteps there. The particle system uses that same table; its
legacy direct properties remain shared accessors. World2D runtime statistics
remain at `world2D.particles.stats`: live, dropped, steps, collisionQueries,
rendered and drawCalls. Workspace exposes Environment -> Particles2D/Particles3D.

## Updating

World2D:update advances physics and particles automatically unless
`autoUpdatePhysics = false`. With explicit scene systems, call
`world2D:updatePhysics(dt)` exactly once from systems/simulation.lua:update2D.
It advances both services and applies only that World2D's timeScale. Existing
3D particles continue through World3D:updateNodes(dt). Do not manually advance
both the system and its owning world in one frame.

The Physics2D example contains a fountain that collides with the scene geometry.
Use Workspace to edit its emitter and LifetimeRamp, and Debug/F4 for solver drawing.

## Shared implementation

`engine/particles/system.lua`, simulation.lua, lifetime.lua, emitterDefinition.lua
and image.lua are common policies. `particles/2d` and `particles/3d` own rendering,
shape sampling and visibility details. Former 3D module paths remain compatibility
entry points. Change shared forces/budgets/lifetime/image behavior once; keep
projection, spatial sampling and renderer-only lighting separate by dimension.

## Images

Both emitters use the common imageMode: Decal, Texture, Tiles, Atlas or XML.
Texture repeat sizes use particle world units; Tiles tileSize combines a fraction
of particle size and world-unit offsets. Missing images display the common checker.

For XML, assign `xml`, clear `texture` to fill its manifest image automatically,
or assign an alternate atlas to texture. `atlasAnimation` selects a named clip;
an empty name uses the manifest initial clip. Each particle plays the XML clip
from its own age without allocating a Flipbook per particle. Atlas mode permits
manual atlasFrame; the existing atlasEnabled/atlasFPS/atlasLoop controls still
provide age-based grid animation and remain compatible with old 3D scenes.

## Ability Runner 2D effects

The scene owns scripts/effects/particles.lua. It adapts the 3D Ability Runner's
DashTrail and AbilityBurst to ParticleEmitter2D: dash emits 100 particles/second,
slide emits 45/second, and each newly reached checkpoint bursts 40 particles.
Lifetimes and caps match the 3D scene; size/speed use the 2D camera's pixel units.
World-space trails remain behind the moving player and fade naturally. Respawn
stops new trail emission. Both effects follow the Player visual layer group.

## Rotating platform and locked particles

Physics2D's MotorArm2D has two Attachment2D children at opposite ends.
LockedPlatformParticles (cyan/blue) uses simulationSpace = 'Local': all existing
particles retain emitter-local positions, so platform translation, rotation and
scale carry them with the attachment. This is the LockedOnPart behavior.
FreePlatformParticles (orange/red) uses 'World': new particles originate from the
moving attachment, while existing particles remain in world coordinates.

ParticleEmitter3D exposes the same simulationSpace setting and semantics. Changing
space affects new births; existing particles keep the space selected at birth.
