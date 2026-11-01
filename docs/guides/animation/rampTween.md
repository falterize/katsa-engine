# Ramp and Tween

Ramp is a Node with reusable sequence data. `mode` is Static or Animated;
Each timeline has its own `interpolation` (Linear or Curve). There is no Application selector: a Static
Ramp with UI color/alpha goals supplies a spatial gradient, an emitter-owned
LifetimeRamp samples particle age, and other targets use property progress.
Values are numbers or equal-length numeric arrays using the existing Vector2,
Vector3 and UDim2-compatible representations. Units are those of the target field:
world units for position/size, degrees for Euler rotation, seconds for playback,
0..1 for transparency, normalized RGB/RGBA for UI/particle color.

```lua
local ramp = world:create('Ramp', {
    name = 'PreparedMove',
    mode = 'Animated',
    playbackTime = 2,
    reverses = true,
    repeatCount = 1,
    reverseDelay = 0.2,
    repeatDelay = 0.5,
    goals = { position = { 40, 10, 0 }, rotation = { 0, 90, 0 } },
}, object)
ramp:connect('Completed', function()
    print('Motion complete')
end)
ramp:play() -- No automatic start at scene creation.
ramp:pause()
ramp:resume()
ramp:stop()
```

`goals` snapshots the current values at play and builds start/end sequences.
`bindings` supplies explicit per-property sequences and overrides a goal with the
same key. Several properties are updated together. Parent is the default target;
Adornee can reference any live same-world node. Physical pose bindings use the
existing teleportLocal API for static/kinematic bodies. They are not swept rigid
motion and do not guarantee moving-platform velocity/continuous collision.
Dynamic-body pose animation is rejected; use forces/impulses instead.

```lua
local data = {
    { time = 0, value = 0, outgoing = { 0.2, 0 } },
    { time = 1, value = 1, incoming = { 0.8, 1 } },
}
local easing = world:create('Ramp', { points = data }, object)
local Tween = require('source.engine.animation.tween')
local track = Tween.new(object, {
    playbackTime = 1.5,
    ramp = easing,
    reverses = true,
    repeatCount = 0,
}, { position = { 20, 5, 30 }, transparency = 0.5 })
track.Started:connect(function()
    print('Started')
end)
track:play()
```

Started fires on play, Completed on the final pass, Stopped on explicit stop from
Playing/Paused, and Resumed on resume from Paused. stop holds the last pose;
play restarts; pause/resume preserve elapsed time. repeatCount=0 means one cycle,
-1 means infinite. With reverses, one cycle includes forward and backward legs.
repeatDelay is between cycles; reverseDelay is between forward/backward legs.
Targets/owners destroyed during scene teardown release scheduled playback and signals.
Only numbers/numeric vectors interpolate; node references, strings and booleans
are not smooth property targets. Euler components are interpolated numerically.

## Sequence format and curves

Each goal's Points editor changes only that goal's Linear/Curve mode. Ramp's
primary Points editor changes its progress/easing curve independently. There is
no duplicate Interpolation field in the Ramp inspector. In code use
`ramp.bindings.position.interpolation='Curve'`; another binding can be Linear.
For primary progress use `ramp.points.interpolation`. The legacy Ramp-level
interpolation is accepted as an import default for timelines without a mode.

A sequence is an ordered array of `{time, value, incoming?, outgoing?}` objects;
0 <= time <= 1, strictly increasing, at least two points. Handles are
`{absoluteTime, normalizedSegmentValue}`. Endpoints have segment values 0 and 1;
handles may overshoot vertically. Handle times must stay monotone within a segment, including implicit default
handles at one-third and two-thirds of that segment. Editor drags clamp to the
opposite effective handle; scripted invalid handle order fails validation early.
Curve evaluation inverts the Bezier time coordinate; it does not assume uniform
Bezier parameter equals timeline time. Scalar progress handles ease all vector
components in that segment; independently shaped channels use separate bindings.
`Ramp:exportData()` returns plain serializable tables, without node handles/signals.

Workspace Goals always offers **+ Add goal**, even for an empty list. Choose a
numeric property from Parent/Adornee, enter a scalar or vector destination and
use **Edit property points** for intermediate values. Remove deletes that goal
and its timeline. Candidate properties follow the target's shared schema and
mode-specific availability; values hidden by a mode remain stored.

Points has a normalized 0..1 graph, exact Time and Value fields, a time slider,
**+ Add point**, **Delete selected**, a New time field and a selectable point list.
Click the line to insert; drag points or orange Bezier handles. Use Plot R/G/B
or X/Y/Z to choose a vector channel. Add initially inserts at .5 and then proposes
the midpoint of the largest remaining interval. Time must stay in 0..1 and strictly
between neighbors; endpoints cannot be deleted. The graph captures a finger drag;
scroll the surrounding controls to reach lower fields. Apply retains all edits;
Cancel restores goals, curves and interpolation together. This is a compact
runtime editor, not Blender's complete curve editor.

Static Ramp:evaluate(t) samples its primary points; Ramp:apply(t) maps scalar
progress through its property bindings. Static does not mean lifetime values are
constant: particle age or UI spatial position supplies the external 0..1 parameter.

## UI gradient and lifetime use

```lua
ui:create('Ramp', {
    goals = { textColor = { 0.1, 0.7, 1 }, textTransparency = 1 },
    bindings = {
        textColor = { { time = 0, value = { 1, 0.3, 0.1 } }, { time = 1, value = { 0.1, 0.7, 1 } } },
        textTransparency = { { time = 0, value = 0 }, { time = 1, value = 1 } },
    },
}, label)
local emitter = world:create('ParticleEmitter3D', { rate = 20 })
emitter.lifetimeRamp.bindings.size = { { time = 0, value = 1 }, { time = 1, value = 0 } }
emitter.lifetimeRamp.bindings.rotation = { { time = 0, value = 0 }, { time = 1, value = 180 } }
```

Gradient uses spatial progress, RGB color and separate alpha goals, Offset/rotation
semantics and multiplicative parent alpha. It preserves stroke separation and can
be placed under UIStroke. Use backgroundColor/backgroundTransparency, textColor/textTransparency or
imageColor/imageTransparency to affect exactly that channel. Under UIStroke use
color/transparency. An Animated Ramp changes real properties over time; to move
a spatial gradient, target its offset/rotation with a second Animated Ramp. GPU gradients
use at most 16 stops; Curve is sampled to 16 values and can approximate sharp bends.

Each emitter owns a Static LifetimeRamp. bindings `size` multiply birth size;
`color` is RGB, `transparency` is 0..1, `rotation` adds degrees to particle spin.
Curve color/alpha output is clamped for rendering. Lifetime is sampled by each
particle's normalized age and does not have independent Animated playback.
