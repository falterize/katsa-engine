# Node authoring and API reference

The normal authoring entry point is `world:create(typeName, properties, parent)`.
Define a scene-owned type under the scene's `nodes/`, list its module in
`settings.nodes`, and inherit the engine implementation of your chosen base.
The renderer, physical world, audio service and other subsystems keep their own
collections, so creating a Lua instance alone is not sufficient for every type.

## Creation functions and class hooks

| Function | Purpose and caller |
| --- | --- |
| `world:registerNodeType(name, definition)` | Define a type in this world only; return its class. Cannot replace an engine class. |
| `Node.define(name, base, registry)` | Lower-level class factory used by engine node modules; defaults to the global registry. |
| `Node.getClass(name, context)` | Resolve aliases and look up a class; context-local types take precedence. |
| `world:create(name, properties, parent)` | Choose the owning service/context and parent, create/mount the node and enable custom processing when needed. |
| `Node.create(name, properties, parent, context)` | Dispatch to the class's inherited/custom mount, or fall back to Node.new. |
| `Class.mount(context, properties, parent)` | Type-specific service constructor; return a mounted node. Context is usually World3D or a UI service, not the new instance. |
| `Node.adopt(table, className)` | Convert the existing table into a node: class/metatable, initializers, typed properties, cleanup and optional existing parent. Return the same table. Already adopted nodes are returned unchanged, even with a different className argument. |
| `Node.new(name, properties, parent)` | Adopt the supplied table and assign the parent; does not run class.mount or independently insert the instance into renderer/audio/physics collections. |
| `Definition.initialize(self)` | Initialize each instance. Base initializers run first, once per class. Parenting/service mounting may still be incomplete. |
| `node:start()` | Optional once-only callback on the first positive-time NodeTree processing pass. |
| `node:update(dt)` | Custom per-node behavior during world processing; dt is seconds. |
| `Definition.register(world)` | Optional scene-module convention called by the scene package for a settings.nodes entry; usually delegates to registerNodeType. |
| `Module.install(Target)` | Ordinary engine module assembly convention; not an automatic per-instance lifecycle hook. |

A typical mounted Mesh3D follows:

```text
world:create -> Node.create -> inherited Mesh3D.mount -> world:addObject
             -> Node.adopt -> base/custom initialize -> parent/service registration
             -> custom setProcess(true) -> start/update on a later world update
```

`adopt` does not copy the supplied table, and `mount` is not a replacement for
`initialize`. A custom Mesh3D normally inherits mount unchanged. Write a mount
only when integrating a new owning service or construction protocol. Resource
cleanup belongs in `onDestroy`; overriding `destroy` can bypass normal teardown.
A method named `release` is not automatically a node destruction hook.

`world:create` automatically registers scene-owned definitions with an update
method for processing. Low-level or global script classes need explicit
`node:setProcess(true)` after attachment to their world. Node hooks are `start`
and `update`; the scene/system hooks `update3D` and `update2D` are separate APIs.

`setProcess(false)` suspends start/update scheduling. `enabled = false` suppresses
behavior updates but does not postpone the first start callback of a scheduled
node. A non-positive world dt skips both. Resuming does not repeat start. Base
initialize callbacks chain automatically; start/update select one method through
inheritance instead of automatically calling every ancestor implementation.

## Common instance methods

All Node descendants inherit these methods unless their type specializes one.
Names use `:` because the instance is passed as self.

| Method | Meaning |
| --- | --- |
| `setParent(parent)` | Reparent, or detach with nil. Validate ownership, cycles and boundaries first; preserve the local pose. Assignment to parent uses the same path. |
| `find(name, recursive)` | First matching child name, or descendant if recursive is true; nil if absent. |
| `isA(typeName)` | Test this type or any base type; recognizes engine aliases. |
| `getChildren()` | Snapshot array of immediate children. |
| `getDescendants()` | Depth-first snapshot of all descendants; does not include self. |
| `findAll(filter, recursive)` | All children/descendants matching name, className and/or tag; combined filters use AND. |
| `findByType(typeName, recursive)` | First match including inherited types. |
| `findByTag(tag, recursive)` | First matching tagged child/descendant. |
| `addTag(tag)` | Add a nonempty string tag; return self. |
| `removeTag(tag)` | Remove a tag; return self. |
| `hasTag(tag)` | Return a boolean. |
| `getTags()` | Sorted snapshot array of tag strings. |
| `attachment(properties)` | Create an Attachment3D child through the low-level node constructor. |
| `setProcess(enabled)` | Enable/disable this world's NodeTree scheduling; requires a live attached node with an update method. |
| `connect(eventName, callback)` | Subscribe to a named signal; return a connection. |
| `emit(eventName, ...)` | Deliver arguments to listeners synchronously. |
| `connection:disconnect()` | Stop a subscription; safe to repeat. |
| `trackConnection(connection)` | Disconnect an external subscription automatically when this node is destroyed. |
| `own(resource)` | Release an exclusively owned resource at destruction; resource must expose release. |
| `onDestroy(callback)` | Register cleanup; callbacks receive the closing node and run in reverse registration order. |
| `destroy()` | Detach, emit destroying, destroy descendants, disconnect listeners and run cleanup; safe to repeat. |

Queries exclude self. Most lookup recursion is opt-in; getDescendants always
recurses. Snapshot arrays can be changed without changing the live hierarchy.
Do not modify children or underscore-prefixed engine state directly. Detaching
retains scene identity; moving scene-owned nodes between worlds requires new
instances. Resources already owned by scene scopes must not also be given to own.

The engine emits `parentChanged(newParent, oldParent)`, `started(node)` and
`destroying(node)`. Other event names are defined by the node or your own code.
Signals and subscriptions are case-sensitive. Destroy disconnects the emitter's
listeners; trackConnection handles subscriptions to other emitters.

## Node3D spatial methods

Positions/sizes use world units; rotations use degrees. Matrix-returning getters
may expose cached engine matrices: copy before modifying them.

| Method | Meaning |
| --- | --- |
| `getLocalMatrix(out)` | Local affine matrix; copies into the optional output. |
| `getWorldMatrix()` | Current exact world matrix, including spatial ancestors and physics. |
| `getRenderWorldMatrix()` | Visual matrix, including enabled physics interpolation; does not change the solver pose. |
| `getLocalTransform()` | Local position/rotation/scale data. |
| `getWorldTransform()` | World position/rotation/scale data, subject to supported affine decomposition. |
| `setLocalTransform(transform)` | Apply authored local transform fields; omitted fields retain their current values. |
| `setWorldTransform(transform)` | Apply a world transform; provide position and rotation, with optional scale. |
| `setLocalMatrix(matrix)` | Decompose and apply a local matrix. |
| `setWorldMatrix(matrix)` | Convert a world matrix through the parent, then apply it. |
| `getWorldPosition(out)` | Exact world position. |
| `getRenderWorldPosition(out)` | Interpolated visual world position. |
| `getWorldCFrame()` | World position/orientation without scale. |
| `setCFrame(frame)` | Set local position/orientation while retaining scale. |
| `setWorldCFrame(frame)` | Set world position/orientation while retaining current world scale. |
| `pointToWorldSpace(point, out)` | Local point to world, including translation. |
| `pointToLocalSpace(point, out)` | World point to local. |
| `vectorToWorldSpace(vector, out)` | Local vector to world, excluding translation; scale still applies. |
| `vectorToLocalSpace(vector, out)` | World vector to local, excluding translation. |
| `setParent(parent, { keepWorldTransform = true })` | Reparent while preserving the world pose when the transform/physics constraints allow it. |
| `getEffectiveOpacity()` | Combined ancestor opacity: product of 1 - transparency. |
| `isVisible()` | Whether self and every ancestor permit visibility; independent of opacity. |
| `getVisibilityState()` | Return both ancestor visibility and combined opacity. |

Optional out tables avoid allocating another return table. Positive scale,
physics-body resizing and shear constraints are described in
[spatial transforms](spatialTransforms.md). A physical pose change should use the
supported transform/body API rather than editing cached matrices.

## Methods specific to built-in types

The common initialize/mount roles above apply to built-in implementations too.
Most methods labeled service-managed below are called by their owning service;
calling them again from gameplay can double-update the same work.

| Type/method | Purpose |
| --- | --- |
| `World3D:create(name, properties, parent)` | Delegate node creation into this root's owned world. |
| `World3D:setCurrentCamera(camera)` | Select that world's camera; nil clears it. |
| `World3D:update(dt)` | Service-managed viewport world step: scaled physics/nodes/cameras and UI. |
| `Body3D:update(dt)` | Refresh body/collider state; does not replace the world's physics step. |
| `Collider3D:descriptor(body)` | Build/cache the backend-neutral collider descriptor and signature. |
| `Collider3D:update(dt)` | Reserved no-op hook in the current implementation. |
| `Constraint3D:releaseJoint(preserveInputs)` | Remove its native joint and invalidate construction state. |
| `Constraint3D:step(dt)` | Physics-managed joint creation/reconfiguration. |
| `Environment:destroy()` | Required environment cannot be deleted independently; deletion is allowed during world teardown. |
| `ClickDetector3D:setAdornee(node)` | Set its target mesh or clear the explicit reference. |
| `ClickDetector3D:getTarget()` | Resolve explicit target or parent. |
| `ClickDetector3D:canActivate()` | Check enabled/live target, visibility, interaction source and radius. |
| `ClickDetector3D:activate(pointerId)` | Emit clicked if activation is allowed; return success. |
| `Decal3D:setAdornee(node)` | Change its surface support node. |
| `Decal3D:update(world, camera)` | Renderer-managed surface/projection refresh. |
| `SurfaceUI:update(world, camera)` | Renderer-managed canvas and face projection refresh. |
| `SurfaceUI:localPoint(x, y)` | Convert screen coordinates to canvas coordinates/depth using its camera. |
| `SurfaceUI:hit(world, camera, x, y)` | Pick a UI node after bounds/interaction/occlusion checks. |
| `Sound:getEnabled()` / `setEnabled(value)` | Read/change effective playback enabled state through property handling. |
| `Sound:setPlaying(value)` | Route playing property assignment into playback control. |
| `Sound:sync(deferApply)` | Audio-managed synchronization of node parameters/effects with its voice. |
| `Sound:getWorldPosition(out)` | Resolve the spatial sound's ancestor position. |
| `Sound:getEmitterMatrix()` | Resolve the spatial sound's ancestor world matrix. |
| `Sound:play()` | Create/resume the voice and play. |
| `Sound:pause()` | Pause the retained voice. |
| `Sound:stop()` | Stop and release its voice/effect bindings. |
| `Sound:isPlaying()` | Actual voice playback state. |
| `Sound:seek(seconds)` | Seek an already loaded voice. |
| `Sound:tell()` | Current playback time, or zero without an active voice. |
| `ParticleEmitter3D:setAdornee(node)` | Change its emission support node. |
| `ParticleEmitter3D:emissionMatrix(render)` | Exact or visual emission frame. |
| `ParticleEmitter3D:getWorldMatrix()` / `getRenderWorldMatrix()` | Specialize spatial getters using the emission frame. |
| `ParticleEmitter3D:emit(count)` | Burst particles; a string first argument instead uses the common signal API. |
| `ParticleEmitter3D:clear()` | Return existing particles to its pool and reset liveCount. |
| `ParticleEmitter3D:setSeed(seed)` | Reset its random generator seed. |
| `Animator:load(identifier, settings)` | Create a track from a clip index, name or clip table. |
| `Animator:transition(name, duration)` | Fade toward the selected state track. |
| `Animator:update(dt)` | Scheduled track advancement and blended pose application. |
| `Animator:applyRootMotion(track)` | Apply root translation from the selected track when configured. |
| `AnimationTrack:setPlaying(value)` | Route property assignment to play/pause. |
| `AnimationTrack:fade(weight, duration)` | Schedule blend weight interpolation. |
| `AnimationTrack:play(fade, speed, weight)` | Restart playback, optionally overriding playback/blend parameters. |
| `AnimationTrack:pause()` / `resume()` | Pause/resume without restarting the timeline. |
| `AnimationTrack:stop(fade)` | Stop immediately or fade out using the configured/default duration. |
| `AnimationTrack:advance(dt)` | Animator-managed timeline/fade/marker advancement. |
| `Ramp:getEnabled()` / `setEnabled(value)` | Read/change effective enabled state and refresh UI/static application. |
| `Ramp:setPlaying(value)` | Route playing property assignment to playback. |
| `Ramp:setAdornee(target)` | Select a live same-world target. |
| `Ramp:evaluate(time, out)` | Sample its sequence at normalized time. |
| `Ramp:apply(time)` | Apply sampled progress/bindings to the target. |
| `Ramp:exportData()` | Copy authored settings into serializable data. |
| `Ramp:play()` / `pause()` / `resume()` / `stop()` | Control the underlying Animated Ramp track. |
| `Ramp:getTarget()` | Resolve adornee or parent. |
| `Ramp:isLifetime()` | Whether it is an emitter's lifetime ramp. |
| `Ramp:isSpatialGradient()` | Whether it represents a static UI color/transparency gradient. |
| `Ramp:addGoal(key, value)` / `removeGoal(key)` | Add/remove an animated property goal and relevant binding. |
| `Ramp:applyLayout(parent)` | UI-layout-managed gradient application. |
| `Ramp:gradientStops(key)` | Produce/cache gradient stop data for the requested channel. |

Specialized camera, billboard and widget implementations can expose additional
methods from their owning services. See [UI layout](../ui/uiLayout.md),
[animation](../animation/playback.md), [physics](../physics/backends.md),
[audio](../audio/audioNodes.md) and [particles](../particles/api.md) for those APIs.

## Internal modules

`NodeTree.new/setProcess/update/release` manage the world's scheduled records.
`Hierarchy.bind` maintains world/tree ownership after parenting. `Parenting.validate`
checks a proposed hierarchy move. `PropertyChanges.initialize/touch/set` maintain
observed fields and cache revisions. `Signals.clear` disconnects an emitter.
`ClassDefinition.install` adds the class factory, and `ClassPolicy.initialize`
chains initializers. `specialNode.register` implements world-owned registration.
These are engine helpers; ordinary node definitions use the public API above.

## A complete scene-owned node

Create `nodes/spinner.lua` in your scene. This is the same module exercised by
`validation/tests/fixtures/lifecycle/basic/nodes/spinner.lua`:

```lua
local Spinner = {
    base = 'Mesh3D',
    properties = {
        spinSpeed = { default = 45, min = -360, max = 360, hint = 'Degrees per second.' },
    },
}

function Spinner.initialize(self)
    self:onDestroy(function()
        self.wasReleased = true
    end)
end

function Spinner:start()
    self:addTag('Animated')
end

function Spinner:update(dt)
    self.rotation[2] = self.rotation[2] + self.spinSpeed * dt
end

function Spinner.register(world)
    return world:registerNodeType('Spinner', Spinner)
end

return Spinner
```

Add `spinner` to `settings.nodes`, preserving any existing entries:

```lua
nodes = { 'spinner' },
```

Then create an instance from your content builder:

```lua
local spinner = scene.world:create('Spinner', {
    name = 'SpinningCube',
    size = { 20, 20, 20 },
    position = { 0, 20, 40 },
    spinSpeed = 90,
}, scene.world.root)
```

The engine handles Mesh3D mounting and schedules the custom update; the scene's
normal world update must still run. Do not also call spinner:update manually.
Properties descriptors provide defaults and editor metadata, not arbitrary
runtime validation of every assignment. Mutable defaults are copied per instance.
For custom constraints, validate inputs in your own methods when required.

`base = 'Node'` is useful for non-spatial logic; `Node3D` adds transforms;
`Mesh3D` adds renderable geometry. Definitions can expose your own ordinary
methods and signals. A node's start/update hooks receive self, not scene state;
store any required application references explicitly instead of assuming globals.

## Scripts, systems and UI code

`scripts/` contains explicitly imported scene code: content builders, data,
helpers and `scripts/ui/`. Merely placing a file there does not schedule it.
`systems/` contains modules enumerated and instantiated by main.lua; its instances
may receive start, update, update3D, update2D and release callbacks.

`main.create` explicitly calls `context:require('scripts.ui.interface').create(state)`.
Interface scenes import `scripts.ui.controller`. Panels/previews stay beneath
scripts/ui. A UI controller that needs independent scheduled behavior can have a
system that uses these modules; the whole UI folder does not need to be a system.
