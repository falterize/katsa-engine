# Particle collisions and lighting

ParticleEmitter3D.collisionGroup uses Physics.collisionGroups, not render LayerGroups.
Workspace offers the same named group list. Change the Collision Groups matrix to
allow or exclude surfaces. Unknown/deleted group names fall back to Default.
Triggers, disabled colliders, canQuery=false and canCollide=false bodies are excluded.

CollisionEnabled performs point-segment rays, not sphere/quad collisions or a full
rigid body per particle. Queries share Particles.collisionBudget per rendered update.
Each particle retains its last checked world position across skipped steps; its next
query spans that deferred path. This fixes crossing a floor during an unqueried step.
The retained path is a straight segment: very curved motion, moving obstacles and
particles spawned inside solids are still approximate. Bounce uses restitution and
collisionFriction; Kill expires the particle. Local-space simulation queries in
world coordinates, then converts the response back to emitter space. At zero budget
collision is deliberately deferred; simulation still advances.

Unlit defaults true, preserving previous appearance. Brightness is a nonnegative
multiplicative gain. Unlit=false uses ambient, the selected directional light and up
to eight enabled local point/spot lights, with two-sided billboard diffuse response.
Particle surfaces currently do not sample shadow maps. Eight local lights follow
world insertion order; this is an explicit fixed shader budget, not full per-particle
light selection. Shader-layer lighting suppression also bypasses lit modulation.

The Particles lab exposes Unlit/Brightness and Collision in its scrollable controls;
use Workspace for the named CollisionGroup and response properties. Its existing
static floor participates in physics. Lower the shared collision budget to inspect
retained sweeps. No FPS or real Android GPU compatibility is asserted without device
measurements.


Example:

```lua
world:create('ParticleEmitter3D', {
    rate = 40,
    lifetime = { 0.8, 1.4 },
    collisionEnabled = true,    -- point-segment rays against colliders
    lightInfluence = 1,         -- lit by ambient, the sun and up to eight local lights
    brightness = 1.5,
})
```
