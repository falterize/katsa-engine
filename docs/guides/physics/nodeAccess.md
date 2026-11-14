# Reaching the physics of a node

A `Body3D` / `Body2D` node is the thing you place in the scene. Its **physics object** is what the
solver simulates. You never create the physics object yourself: it appears as `node.physics` as soon
as the node is created, and every physics method lives there.

```lua
local ball = world:create('Body3D', { position = { 0, 20, 0 }, size = { 2, 2, 2 } })

ball.physics:applyImpulse({ 0, 40, 0 })   -- every physics method is on node.physics
ball.velocity = { 5, 0, 0 }               -- the common state is also a node property
```

## The four names

| You write | What it is | Typical use |
| --- | --- | --- |
| `node.physics` | The physics object of one node (`Body3D` / `Body2D` class of the engine). | `teleport`, `applyImpulse`, `setVelocity`, `getContacts`, ... |
| `node.physics.node` | The node that owns this physics object. | From a raycast hit, a contact or a callback back to the scene object. |
| `node.physics.space` | The physics world this body lives in (3D: `world.physics`, 2D: `ui.physics2D`). | `raycast`, gravity, collision groups, interpolation, stepping. |
| `node.physics.raw` | The backend-native body (Oimo / Jolt in 3D, Box2D in 2D). | Rare, backend specific. **Not portable.** |

Reading it as a chain: `node` has a `physics`; that `physics` lives in a `space` and wraps a `raw`
body; it points back to its `node`.

```lua
local p = ball.physics
p.node == ball                 -- true
p.space == world.physics       -- true  (the whole simulation: queries, groups, gravity)
p.raw                          -- the native Oimo / Jolt / Box2D body
```

`node.physics` is `nil` for nodes without a body (a `Folder`, a `Mesh3D` that nobody added a body to).
`World3D` / `World2D` keep their own *space* in `.physics` / `.physics2D`; that is a physics
**space**, not a body, and it has no `.node`.

## Where `.node` is available

Every physics object knows its node, so any API that hands you a physics object gives you the node:

```lua
local hit = world:raycast({ 0, 50, 0 }, { 0, -50, 0 })
if hit then
    print(hit.node.name)        -- the node that was hit
    hit.physics:applyImpulse({ 0, 10, 0 })   -- and its physics object
end

ball:connect('contactBegin', function(other)   -- `other` is a physics object
    print(other.node.name)
end)
```

A backend-native `raw` body maps back through the space:

```lua
local physics = space:physicsOf(raw)   -- the physics object, or nil
local node = space:nodeOf(raw)         -- the node, or nil
```

## Methods on `node.physics`

Same names in 3D and 2D unless noted. Vectors are plain tables (`{ x, y, z }` / `{ x, y }`), units are
world units per second; `getVelocity(out)` fills `out` and returns it, so hot loops allocate nothing.

| Group | Methods |
| --- | --- |
| Pose | `teleport(position, rotation)`, `teleportLocal(position, rotation)`, `sync()` |
| Velocity | `setVelocity(v)`, `getVelocity(out)`, `setAngularVelocity(v)`, `getAngularVelocity(out)`, `getPointVelocity(position, out)` (3D) |
| Forces | `applyForce`, `applyImpulse`, `applyTorque`, `applyAngularImpulse`, `applyForceAt(value, position)`, `applyImpulseAt(value, position)` |
| Mass | `setMass(value)`, `getMass()` |
| Collider | `setCollider(descriptor)`, `addCollider(descriptor)` (3D), `refreshFilters()` |
| Sleep | `isSleeping()`, `wake()`, `sleep()` |
| Settings | `set({ friction = ..., restitution = ..., ... })` |
| Contacts | `getContacts()` |
| Lifetime | `destroy()` (also done when the node is destroyed) |

Angular velocity is in **radians per second in 3D** and **degrees per second in 2D** (the same unit as
the node's `rotation`).

All of these are safe to call from contact callbacks and while the solver runs: changes are queued
and applied right after the step.

## Properties on the node

Settings you author stay properties of the node: `mass`, `density`, `friction`, `restitution`,
`gravityScale`, `linearDamping`, `angularDamping`, `bodyType`, `isTrigger`, `canCollide`,
`canQuery`, `collisionGroup`, `autoSleep`. In addition the node has live solver state:

| Property | Access | Meaning |
| --- | --- | --- |
| `velocity` | read / write | Linear velocity. Writing calls `physics:setVelocity`. |
| `angularVelocity` | read / write | Angular velocity (units above). |
| `isSleeping` | read only | True while the solver has put the body to sleep. |

`velocity` and `angularVelocity` return a **new table on every read**. In a per-frame loop prefer
`node.physics:getVelocity(scratch)` with one table you keep. The Workspace inspector shows the three
properties read only.

```lua
ball.velocity = { 0, 12, 0 }          -- set once, readable code
local v = ball.velocity               -- fresh table, fine for occasional use

local scratch = {}
function update(dt)
    ball.physics:getVelocity(scratch)  -- no allocation
    if scratch[2] < -30 then ... end
end
```

## Queries

`world:raycast(from, to, filter, out)` (3D `World3D`, 2D `World2D`) returns the nearest hit or `nil`:

| Field | Meaning |
| --- | --- |
| `hit.physics` | The physics object that was hit. |
| `hit.node` | Its node. |
| `hit.position`, `hit.normal` | World position and surface normal. |
| `hit.fraction` | Distance along the segment, 0..1. |
| `hit.collider` | 2D only: the collider descriptor that was hit. |

`filter(physics, collider)` returns `false` to skip a body. Pass an `out` table to reuse it between
frames. The same call exists on the space (`node.physics.space:raycast(...)`); 2D also has
`raycastAll`. The 2D contact events carry `physics0` / `physics1` and `node0` / `node1`.

## The raw body

`node.physics.raw` is the object of the physics library behind the engine (Oimo or Jolt in 3D,
Box2D in 2D). Use it only for something the engine API does not offer. The engine does not promise
that these objects keep the same methods, units or behaviour between backends: code that touches
`raw` works with one backend only, and changes made through it bypass the engine's deferred
updates, unit conversion and interpolation. Prefer `node.physics`.

## Migration from `node.body`

`node.body` and `body.object` / `body.physics` no longer exist.

| Before | Now |
| --- | --- |
| `node.body` | `node.physics` |
| `node.body.object` | `node.physics.node` |
| `node.body.physics` (the physics world) | `node.physics.space` |
| `node.body.raw` | `node.physics.raw` |
| `hit.body` | `hit.physics` (and `hit.node`) |
| 2D event `body0` / `body1` | `physics0` / `physics1` (and `node0` / `node1`) |
