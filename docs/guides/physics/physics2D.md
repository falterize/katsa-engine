# 2D physics and Camera2D

Katsa uses LÃ–VE's built-in Box2D for 2D and the existing Jolt/Oimo integration for
3D. Select **Physics 2D** or **Physics 2D + 3D** in the example menu. Both examples
own their full code, assets and system startup inside their scene folders.

## Create a physical world

Scene settings can contain:

```lua
physics2D = {
    unitsPerMeter = 64,
    gravity = { 0, -627.84 },
    fixedDelta = 1 / 60,
    maxSteps = 8,
    velocityIterations = 8,
    positionIterations = 3,
    interpolate = true,
    debug = true,
},
```

During content creation:

```lua
local physics = scene:createPhysics2D()
local ui = scene.ui
local camera = ui:create('Camera2D', {
    name = 'Camera2D',
    position = { 640, 360 },
    rotation = 0,
    fov = 60,
    referenceHeight = 720,
    zoom = 1,
})
local floor = ui:create('Body2D', {
    name = 'Floor2D',
    bodyType = 'Static',
    position = { 640, 0 },
    size = { 1000, 24 },
})
local ball = ui:create('Body2D', {
    name = 'Ball2D',
    position = { 400, 300 },
    restitution = 0.4,
    bullet = true,
})
local collider = ui:create('Collider2D', {
    shape = 'Circle', radius = 20, size = { 40, 40 },
}, ball)
local visual = ui:create('Frame', {
    size = { 1, 0, 1, 0 }, backgroundColor = { 0.27, 0.7, 0.9 },
}, collider)
ui:create('UICorner', { radius = { 0.5, 0 } }, visual)
```

Use `ui:createPhysics(options)` directly for an additional World2D. Each UI world
owns its native simulation and active Camera2D. World3D:create also routes 2D
classes to their World2D ancestor, or the first UI world when no parent is given.
Physical worlds are screen World2D roots; billboard and surface UI are not
physical worlds. HUD widgets remain camera-independent. UI visuals may also belong to spatial Node2D,
Body2D or Collider2D nodes and follow their world transform and Camera2D.

The module entry points are `source.engine.physics.2d` and
`source.engine.physics.3d`. The historical `source.engine.physics` entry still
selects 3D. Implementation folders and physical node folders are categorized by
dimension; new class names end in `2D` or `3D`.

## Runner example and pixel animation

Select **Ability Runner 2D** (`abilityRunner2D`), or run `katsa . --scene abilityRunner2D`.
The complete scene lives in `source/game/scenes/abilityRunner2D`, including its level,
controller, atlas, UI and systems. A/D or touch buttons move; Space double-jumps, Shift
dashes, C slides and R respawns. Gold trigger volumes save checkpoints, red lava is a
kill-zone, and the green finish trigger completes the course.

`assets/textures/player.png` is a 64x8 atlas with eight hand-authored 8x8 frames.
`assets/animations/player.xml` defines Idle/Run/Jump/Dash/Slide clips, frame indices,
rates, looping and atlas properties; `scripts/animation/player.lua` creates playback
from the sprite's manifest.
`systems/animation.lua`
updates the reusable `engine/animation/flipbook.lua` module using World2D time.
The ImageRect declares `imageMode = 'XML'` and `xml = 'scene://animations/player.xml'`.
The manifest configures the image, atlas grid and nearest filtering automatically.
Only frame changes invalidate its pixel cache; nearest filtering preserves the pixel grid.

All three physics examples use the common collapsible scene-controls widget, Workspace,
Stats, Debug and Tools. Gameplay touch buttons stay directly accessible, like the 3D
runner. Free-3D-camera UP/DOWN buttons are hidden when no 3D camera is active.

### Edit the player animation XML

Edit [player.xml](../../../source/game/scenes/abilityRunner2D/assets/animations/player.xml).
The root `flipbook` element declares format version 1, image path, atlas columns/rows,
8x8 frame dimensions, `pixelate` and initial state. Each named `animation` has `fps`
and `loop`; its self-closing `frame` children define the playback order.

```xml
<animation name="Run" fps="10" loop="true">
    <frame index="2" />
    <frame index="3" />
    <frame index="4" />
    <frame index="3" />
</animation>
```

Indices start at zero, left to right and then top to bottom. `loop="false"` holds
its last frame. Keep the controller's state names (`Idle`, `Run`, `Jump`, `Dash`,
`Slide`) when editing this example. Art stays in the PNG atlas; gameplay state
selection stays in Lua. The XML contains the animation data without duplicated Lua
clip tables or atlas dimensions.

`engine/animation/formats/flipbookXml.lua` reads the documented manifest schema,
validates frame bounds and the real atlas size, and configures an ordinary
`Flipbook` instance. It accepts comments, single/double quoted attributes and the
five standard named attribute entities; unknown tags/attributes and declarations
are rejected with errors. Other code may continue using `Flipbook.new(target, clips)`
with Lua tables; this runner uses XML. Reaching a new checkpoint plays the same
shared chime at the same volume as the 3D Ability Runner. Re-entering an activated
checkpoint does not replay it.

## Visual hierarchy and opacity

Use `World2D -> Node2D (optional group) -> Body2D -> Collider2D -> ImageRect/Frame`.
Alternatively attach a visual directly to Body2D or Node2D. A collider is geometry,
not a drawable material; native shapes appear only in the physics debug overlay.
The examples now explicitly author their collider and visual children.

Widget UDim2 values resolve against the spatial parent's local `size`. In particular,
`size = { 1, 0, 1, 0 }` fills that rectangle, centered on its spatial origin.
Set the collider's layout size to the intended visual bounds (for a radius-20 circle,
use `{ 40, 40 }`). Point-defined geometry and its visual remain independently editable,
as mesh geometry and Collider3D are independent in 3D. UI descendant clipping is local
to this rectangle; bodies and cameras may move, rotate and scale the resulting surface.
Images use ordinary `scene://` and `shared://` paths. Buttons, sliders and scroll frames
use inverse world/camera transforms for pointer input; callbacks still receive screen
coordinates. HUD is drawn above spatial surfaces. Sibling spatial surfaces follow
insertion order; widget siblings use ZIndex without changing the authored hierarchy.

World2D `transparency` / `Transparency` is in 0..1 and composites the whole world,
including its HUD, physical visuals and debug geometry. Fully transparent worlds do
not capture pointers. This changes visibility, not simulation or timeScale. Node2D
transparency affects descendant visuals; Collider2D has no material transparency field.
Local visual surfaces cache pixels until their content changes. Raster density includes
DPI, camera projection and group scale; rigid movement reuses canvases.

World3D defines fixed coordinates and exposes no Position, Rotation, Scale or Size
settings in Workspace. Node3D retains its grouping transforms.

## Per-world gravity

Both world types expose scalar `gravity` / `Gravity` and vector
`gravityDirection` / `GravityDirection`. Magnitude is acceleration in world units/s^2.
World3D defaults to 196.2 in direction `{ 0, -1, 0 }`; World2D defaults to 627.84
in direction `{ 0, -1 }` (9.81 times the default units per meter).
Directions are normalized for simulation; a zero direction or magnitude disables gravity.

```lua
scene.world.root.gravity = 196.2
scene.world.root.gravityDirection = { 0, -1, 0 }
scene.ui.gravity = 627.84
scene.ui.gravityDirection = { 1, 0 }
```

Edits apply on the next physics update and wake dynamic bodies. Worlds are independent;
changing gravity does not change their timeScale. Existing solver `gravity = { x, y, z }`
(or `{ x, y }`) settings remain supported and populate world properties when the solver
is created. Solver options also accept a scalar `gravity` plus `gravityDirection`.
Explicit World2D/viewport World3D properties authored before solver creation take priority.
The direct `physics:setGravity(...)` API synchronizes the inspector's magnitude and
direction. Native world calls bypass this API and should be reserved for backend code.

## Coordinates and properties

Node2D positions and collider dimensions are ordinary two-component world-unit
vectors. X points right, Y points up; rotations and angular velocities use
counterclockwise degrees and degrees/second. They are independent of UDim2 UI layout.
Node2D is a spatial group with `position`, `rotation` and Vector2 `scale`, just
as Node3D is a group with 3D transforms. Scale defaults to `{ 1, 1 }`; components
must be finite and nonzero. Parent scale affects child offsets, geometry and UI
visuals. Rotated nonuniform groups preserve their complete affine transform,
including shear. `getWorldTransform()` returns six affine components and the
accumulated rotation in degrees; `getWorldPose()` / `setWorldPose()` retain their
position-and-angle API. Native body poses remain rigid; scale/shear are baked
into fixtures only when geometry changes. Uniform circles stay analytic circles;
nonuniform circles use a 64-segment polygon approximation within `maxFixtures`.
Node2D/Body2D/Collider2D have no render color, ZIndex or bitmask Layers setting.
Color and UI depth belong to their visual widgets.

`unitsPerMeter` defaults to 64 (`units` remains accepted). Gravity, velocity and
lengths use world units; forces use kg*world-unit/s^2, impulses kg*world-unit/s,
torques kg*world-unit^2/s^2. Density is kg/m^2 and explicit mass is kg. Conversion
is per world; do not call `katsa.physics.setMeter` while worlds exist.

Body2D supports `Static`, `Dynamic` and `Kinematic`, density/mass, friction,
restitution, gravityScale, linear/angular damping, sleeping, fixedRotation,
bullet continuous-collision detection, enabled, canQuery, canCollide, isTrigger
and collisionGroup. `enabled = false` deactivates the native body. `visible`
controls its visual subtree independently. Collision groups remain separate from rendering.

Body2D without Collider2D children has its fallback `collider` descriptor, normally
a box using its size. Explicit Collider2D children replace that fallback and form
a compound body. Disabled explicit children create no fixture; removing every
explicit child restores the fallback. Changes are observed without replacing
unchanged fixtures. Polygon, image, edge and chain authoring is covered in the
[editable collider guide](pointColliders.md).

## Simulation time

The common scene main pattern is:

```lua
function Scene.update2D(state, dt, realDt)
    state.scene.ui:update(realDt or dt, dt)
    state.scene.systems:update2D(dt, realDt)
end
```

`UI:update(realDelta, simulationDelta)` advances its physical world automatically,
once, while retaining separate wall time for widgets. The second argument is
the application simulation delta before the owning World3D time scale. World2D applies its own timeScale; zero freezes physics. If
omitted, the first argument is used with World2D.timeScale. `physics.paused = true`
pauses only that physical world. Existing scene mains pass both deltas.

The provided examples explicitly set `ui.autoUpdatePhysics = false` in content creation.
Their `systems/simulation.lua` owns `Simulation:update2D(dt)` and calls
`state.scene.ui:updatePhysics(dt)` exactly once. Disabling that system freezes the
solver while keeping menus responsive. The mixed example keeps its separate 3D update.
Camera tracking is refreshed after the manual 2D step. For another scene, set
`ui.autoUpdatePhysics = false`, then call
`ui:updatePhysics(dt)` from exactly one scene system. This helper applies that
World2D timeScale. Direct physics:update(dt) remains available when the caller
explicitly owns all time conversion. Do not also step it from UI.
`beforeStep` and `afterStep` callbacks run for each fixed tick. Catch-up is bounded
by maxSteps; stats records dropped time rather than looping without a bound.
Visual interpolation does not change solver poses or the fixed simulation rate.

Every World2D has its own timeScale (0..100), exposed in Workspace. Every
World3D retains its own root.timeScale. A World2D does not inherit its enclosing
World3D clock: one world can be paused while another continues, including its
processed Node2D scripts. UINode scripts and UI animation time use the same local
2D clock. Reparenting a generic script changes its clock owner. Nested viewport
World3D clocks are also independent of the surrounding World2D scale.

The existing manager.time.scale remains an optional application-wide simulation
multiplier and is labeled Global time in Tools. It is separate from per-world
settings. The new examples have explicit 2D time and 3D time buttons for checking
independent speeds and pauses.

## Body operations and queries

`node.physics` exposes (see `nodeAccess.md`):

```lua
ball.physics:setVelocity({ 120, -80 })
ball.physics:applyImpulse({ 0, -40 })
ball.physics:applyForceAt({ 50, 0 }, { 400, 100 })
ball.physics:teleport({ 400, 100 }, 45)
local velocity = ball.physics:getVelocity()
local mass = ball.physics:getMass()
```

Scalar conveniences include `setLinearVelocity(x, y)`, `getLinearVelocity()`,
`getPosition()`, `applyForce(x, y, px?, py?)` and `applyImpulse(x, y, px?, py?)`.
Also available: get/setAngularVelocity, applyTorque, applyAngularImpulse, setMass,
set(settings), setCollider, teleportLocal, sleep, wake, isSleeping, getContacts
and destroy. Node destruction releases the wrapper automatically.

```lua
local hit = physics:raycast({ 0, 100 }, { 1000, 100 })
local hits = physics:raycastAll({ 0, 100 }, { 1000, 100 })
local pointBodies = physics:overlapPoint({ 400, 100 })
local boxBodies = physics:overlapBox({ 400, 100 }, { 100, 80 })
local circleBodies = physics:overlapCircle({ 400, 100 }, 50)
```

Rays return physics, node, collider, fraction, position and normal. raycastAll sorts hits;
compound bodies can contribute multiple fixture hits. Overlaps return unique body
wrappers and perform exact fixture tests after AABB traversal, including every
chain segment. Optional filters receive `(bodyWrapper, colliderNode)`; overlaps
and the nearest ray accept an optional reusable output table. Queries honor
canQuery and active fixtures. As in Box2D, a ray starting inside a solid shape
does not report an entry hit for that shape. Queries are not reentrant.

## Contacts, triggers and groups

```lua
ball:connect('collisionEnter', function(otherNode, contact)
    print(otherNode.name)
end)
ball:connect('triggerEnter', function(otherNode, contact)
    otherNode:destroy()
end)
physics:setGroupsCollidable('Player', 'Decoration', false)
ball.collisionGroup = 'Player'
```

Events: collisionEnter, collisionExit, collisionHit, triggerEnter and triggerExit.
The event contains physics0/physics1, node0/node1, collider0/collider1, sensor, position (if available)
and normal directed from physics0 to physics1. collisionHit includes normal impulse.
Fixture contacts are counted separately for trigger and solid channels, emitting
one enter/exit per body pair/channel. User callbacks run after native stepping
unlocks; destruction and queued changes are then flushed safely.

The 3D-style aliases triggerEntered/triggerExited and
collisionEntered/collisionExited pass the other body wrapper. Low-level wrapper
callbacks use the shorter names and receive `(self, otherWrapper, event)`.
`physics.collisionGroups` exposes the shared group registry, including add,
set, rename and remove. `canCollide = false` suppresses contacts unless the body
or fixture explicitly acts as a trigger. Querying remains independently enabled.
Box2D generates solver contacts when at least one participating body is Dynamic;
static/static and kinematic/static pairs require explicit overlap queries.

## Constraints

```lua
local a = ui:create('Attachment2D', { position = { 0, 0 } }, floor)
local b = ui:create('Attachment2D', { position = { 0, -20 } }, ball)
local rope = ui:create('RopeConstraint2D', {
    attachment0 = a,
    attachment1 = b,
    maxLength = 250,
    allowCollision = false,
    breakForce = 2000,
})
```

| Node | Behavior / main settings |
| --- | --- |
| HingeConstraint2D | Revolute joint, degree limits, motorSpeed, motorForce as maximum torque |
| BallSocketConstraint2D | Hinge analogue in a plane; unconstrained rotation by default |
| PrismaticConstraint2D | Slide along attachment0's X axis; linear limits/speed/motor force |
| WeldConstraint2D | Rigid relative transform by default; frequency/dampingRatio optionally soften it |
| RopeConstraint2D | Maximum distance; maxLength or length |
| SpringConstraint2D | Distance spring with length, frequency and dampingRatio |
| DistanceConstraint2D | Fixed distance with length |
| WheelConstraint2D | Suspension along attachment0's X axis and optional rotational motor |
| FrictionConstraint2D | maxForce and maxTorque |
| MotorConstraint2D | maxForce, maxTorque, correctionFactor, optional linearOffset/angularOffset |
| PulleyConstraint2D | groundAnchor0/groundAnchor1 in world units, positive ratio |
| GearConstraint2D | joint0/joint1 reference hinge/prismatic nodes; ratio couples them |
| MouseConstraint2D | attachment1 body follows world-space target; maxForce/frequency/dampingRatio |

Most constraints require attachments on two different bodies in the same world.
MouseConstraint2D only needs attachment1. Gear endpoints can be inferred from its
source constraints. Static anchor bodies are useful for attaching mechanisms to
the world. Reaction forces/torques feed break thresholds; `repair()` reconnects a
broken constraint. `enabled = false` releases its joint, and re-enabling rebuilds
it. A moving body does not cause joint reconstruction. Endpoints and dependent
gears are released before their native owners. Status explains waiting/disabled/
active/broken state. Three-dimensional swing/twist and six-axis constraints have
no direct 2D counterpart and are not exposed under misleading 2D names.

## Camera2D

Position, rotation, zoom, fov, referenceHeight, drawDistance and layer masks
control the 2D view. At 60 degrees, zoom 1 and referenceHeight 720, a 720-high
viewport shows 720 world units vertically. A wider FOV shows more; higher zoom
shows less. This remains an orthographic plane: there is no perspective depth
or 3D near/far clipping. Vertical world coverage remains stable when the viewport
resizes; aspect ratio determines horizontal coverage.

`getFocalLength()/setFocalLength(value)` convert vertical FOV to/from the same
reference-height convention. `getVisibleSize(width, height)` returns world extent.
`screenToWorld/worldToScreen` use coordinates within the logical viewport.
`project(point)/unproject(x,y)` use the owning World2D dimensions. For actual
window mouse/touch coordinates, use `ui:screenToWorld2D` and
`ui:worldToScreen2D`; these also account for UI scaling and letterboxing.

The newest Camera2D becomes current unless `current = false`; select explicitly
with `ui:setCurrentCamera(camera)`. Optional followTarget and offset snap to the target
with no smoothing. Implement custom interpolation in scene code if needed.
Camera transforms do not affect screen HUD layout or 3D cameras.

## Debugging and coexistence

`physics.debug` has enabled, shapes, joints, centers, velocities and contacts.
Debug geometry uses the solver pose, making interpolation differences visible.
Both examples use the same navigation, Workspace, Tools and Debug as the older scenes. F2 opens Workspace; F4 opens Debug. The group editor has separate 2D/3D collision matrices, and attachment/camera target pickers enforce the correct dimension and owner. Existing Debug menus expose these switches. New scenes provide touch-friendly
buttons for debug switches, pause, impulse and Camera2D FOV. F3 opens Stats with
2D body/fixture/contact/joint/sleep counts, timings, steps and dropped time; the
existing histories and 5/30-second CSV export include these numeric metrics.

2D and 3D simulations own separate native worlds. They coexist and can exchange
gameplay events but do not collide directly across dimensions. Box2D runs through
LÃ–VE on the main thread; the existing Jolt worker configuration is unchanged.
No extra Box2D DLL, copied source tree or vendor package is required.

The example Main scene button uses the bootstrap-provided manager.sceneFactory and manager.startScene, so exported scene packages do not depend on the demonstration catalog.

## Layers and direction indicators

Visual UI elements (including visual modifiers/gradients) and SurfaceAppearance3D
expose `layerGroup` / `LayerGroup`. They use the existing named world layer registry.
World2D.layerGroup is the HUD viewer group; Camera2D.layerGroup is the spatial 2D viewer
group. Billboard/surface UI and material contributions use the rendering Camera3D.
Hidden visual layers do not capture pointers; collision groups and simulation are unchanged.
Parent visual visibility still gates its subtree. Material-layer filtering selects material
contributions without hiding the Mesh3D itself; its fallback material remains available.

```lua
scene.world.layerGroups:add('Effects')
scene.world.layerGroups:add('HUDViewer')
scene.ui.layerGroup = 'HUDViewer'
label.layerGroup = 'Effects'
scene.world.layerGroups:set('HUDViewer', 'Effects', false)
```

Open Debug / F4 and enable **2D orientation axes** and/or **3D orientation axes**.
The center indicators show X in red, Y in green and Z in blue for 3D; they rotate with
the active cameras. A depth-aligned axis uses a circle. Without an active 3D camera,
its indicator is explicitly labelled. Code can set `scene.world.debug.orientation2D`
and `orientation3D`. Both start disabled and do not change simulation or scene transforms.

Spatial 2D coordinates now use Y up, so downward gravity is `{ 0, -1 }` in 2D and
`{ 0, -1, 0 }` in 3D. Camera2D performs the conversion to LÃ–VE's Y-down screen space.
World2D without Camera2D projects origin at the lower-left corner. UI descendants of
a spatial node retain their ordinary top-left, Y-down local layout; their surfaces and
pointer inversion handle the coordinate conversion. Image collider alpha rows are
converted consistently. Existing first-party 2D examples have been migrated; custom
Y-down spatial data must negate Y and rotation, while ordinary HUD UDim2 stays unchanged.

## Camera follow and interpolation

Camera2D `followTarget` tracks the pose that is drawn. With Physics2D interpolation enabled this is the blend of the
previous and current solver step, so the camera and interpolated spatial visuals move together at any frame rate or
World2D timeScale. Disable `interpolate` to follow the raw solver pose.
