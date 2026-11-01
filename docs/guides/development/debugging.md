# Debug settings and error reports

Every World2D and World3D automatically owns exactly one required Environment.
It cannot be independently deleted, duplicated or moved to another world.
Workspace groups settings beneath it:

- World2D -> Environment -> Debug -> Physics2D: enabled, shapes, joints,
  centers, velocities and contacts; Debug itself contains the 2D orientation axes.
- World2D -> Environment -> Particles2D: wind, particle/query budgets and fixed steps.
- World3D -> Environment -> Debug -> Physics3D / Gizmos: visualizer controls;
  Debug itself contains wireframe, bones and 3D orientation axes.
- World3D -> Environment -> Particles3D, Lighting, Shadows, Sky, Fog and Rendering.
  Ambient light, brightness, exposure and tone mapping are on Environment itself.
  World2D Environment exposes ambient and brightness for lit particles.

These are categorized Settings rows, backed by the same tables used at runtime.
There is no separate Physics2D Solver Settings row. Solver configuration remains
in scene physics settings and the runtime API; F4 groups pause/step commands
for both dimensions. Gravity, gravityDirection, timeScale and currentCamera stay
on their owning world because they control the simulation and active view.

```lua
local environment = scene.ui.environment
-- Settings exist even before physics or particle emitters are created.
environment.debug.physics.enabled = true
environment.particles.maxParticles = 2048
environment.particles.wind = { 20, 0 }
scene.ui.currentCamera = scene.ui:create('Camera2D', { fov = 60 })
```

Debug/F4 has separate tabs for 2D Physics, 3D Physics, Rendering, Directions and
Diagnostics. The 2D physics tab controls the scene's primary World2D; use Workspace
for another World2D. Each tab has its own compact list and visible active state.

Lua errors keep their window open; close it explicitly to exit. Ctrl+C copies the
traceback and the wheel scrolls it. Reports are saved in the save directory,
crashes/crash-01.log through crash-10.log, newest first, each with the last 50 console lines;
`last-error.log` is a copy of the newest report. See the [console and logs guide](console.md). Automated test/smoke modes still exit
on failure. A native driver/process fault cannot be kept alive by Lua's handler.
