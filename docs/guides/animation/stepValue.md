# Smoothing per-tick state

Physics advances in fixed steps and bodies are drawn by interpolating between their previous and
current step. State that gameplay code authors once per step (facing angle, animation blend
weights, lean) has no such history. When the world clock is slowed, a 60 Hz step may happen only
every few rendered frames, so those values change in visible jumps while the body still moves smoothly.

`source.engine.animation.stepValue` stores the previous and current value and samples them with the
same alpha used by interpolated bodies.

```lua
local StepValue = require('source.engine.animation.stepValue')

local yaw = StepValue.new(0, true) -- true: angular, blends along the shortest arc
-- Once per fixed step, from beforeStep or afterStep:
yaw:capture(player.facing)
-- Every rendered frame:
model.root.rotation[2] = math.deg(yaw:sampleFor(physics))
-- After a teleport or scene start, drop stale history:
yaw:reset(player.facing)
```

`sampleFor(physics)` returns the newest value when physics is paused or interpolation is disabled,
matching Body3D. `sample(alpha)` accepts an explicit 0..1 alpha. Capture exactly once per step; capturing
per frame defeats the purpose.

Camera2D now follows the interpolated pose of its target, so a camera following a Body2D no longer
drifts against interpolated spatial visuals between fixed steps.
