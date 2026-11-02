# Background execution and time scale

A scene is *focused* while its window is in front and *unfocused* when the window is minimised or
another application has the focus. What runs in the second case is decided per scene.

| Setting / hook | Where | Effect |
| --- | --- | --- |
| `runInBackground = true` | scene `settings.lua` | the scene's full `update` keeps running while unfocused |
| `updateInBackground(dt, realDt)` | scene state / `Game` | runs *only* this while unfocused (network, physics, AI) |
| debug menu *Run in background* | Debug / F4 | overrides the setting for the current run |

Default is `false`: an unfocused scene freezes. A **server must not freeze**: a hosting player
who alt-tabs would stop the bot, the physics and every connected client, so networked scenes
define `updateInBackground` (multiplayerCars does: it steps physics and the server).

```lua
-- scenes/<name>/settings.lua
return { id = 'arena', runInBackground = false }

-- scenes/<name>/scripts/content.lua   (state returned from create)
function state:update(dt)              -- focused: everything
    self:updateNetwork(dt)
    self:updateInput(dt)
    self:updateCamera(dt)
end

function state:updateInBackground(dt, realDt)   -- unfocused: only the simulation
    self:updateNetwork(dt)                      -- physics step + server tick
end
```

## Which delta you receive

* `dt` is the *scaled* delta: real time multiplied by the scene's time scale (the
  `World3D.TimeScale` / `timeScale` of the world, the debug menu slider and pause). Focused and
  unfocused updates receive the same kind of value, so a host that sets TimeScale 5 sees the bot
  move at 5x whether or not the window has focus.
* `realDt` is unscaled wall-clock time, for things that must not speed up (network timeouts,
  reconnect timers, voice capture).
* `Game:updateInBackground` and `Interface:updateInBackground` apply the world clock
  (`engine/world/clock.delta`) so node animation and physics follow TimeScale too.

## Physics in the background

Fixed-step physics (`fixedDelta`, `maxSteps`) catches up with the elapsed time up to `maxSteps`
steps per call, so a slow background tick is absorbed rather than dropped. With
`interpolate = true` the renderer reads `physics.interpolationAlpha` and
`node:getRenderWorldMatrix()` (or `StepValue:sampleFor(physics)`) so motion stays smooth even at
TimeScale 10.

## Checklist for a networked scene

1. `runInBackground = true` or an `updateInBackground` that steps physics and the server.
2. Use `realDt` for connection timers; `dt` for gameplay.
3. Do not rely on window focus callbacks: query `scene.manager.focused`.
