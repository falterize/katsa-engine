# Stare Shooter scene

The supplied Godot project is available as `stareShooter` in the example selector.
Run it directly with `katsa . --scene stareShooter`; add `--physics-jolt` or
`--physics-oimo` to choose a backend. Change `startScene` in
`source/game/data/project.lua` to make it your game's entry scene.

## Controls

| Input | Action |
| --- | --- |
| WASD | Camera-relative movement |
| Left Shift | Run |
| Space, held | Jump; can jump again after landing |
| Left Ctrl or C | Crouch; jumping is unavailable while crouched |
| Mouse | Look, 0.25 degrees per pixel |
| Mouse wheel | One-meter zoom steps, clamped to 0–100 meters |
| Q, held | Align the character to the camera; reverse the walking clip when moving backward |
| Tab / Engine menu screen button | Release the cursor and show engine menus; press again to resume |
| F2 / F3 / F4 | Workspace / Stats / debug tools; temporarily release character input |
| F6 | Toggle the optional retro screen shader |
| Escape | Engine pause menu |

The original camera starts at zero spring-arm distance, with its -0.5 m child
offset preserved. Scroll down to see the animated character from behind. The
large character at the left is the source's static HUD image, not the player.
The second image is a world-space billboard at the original location.

Set `presentation.menuKey` in this scene's `settings.lua` to a key name
(default `'tab'`). `presentation.menuButton = true` enables the bottom-right
**Engine menu / Resume game** button for touch and pointer input. Both controls
show Navigation, Workspace and Debug; Tools, Stats and the audio mixer remain
available through their normal buttons. Returning to gameplay closes these
panels and clears held movement/look input. The simulation continues while
inspecting; use Pause or time scale to stop it.

## Scene ownership

Everything specific to this game lives in `source/game/scenes/stareShooter`.

| Location | Responsibility |
| --- | --- |
| `settings.lua` | Player tuning, camera tuning, backend and presentation defaults |
| `main.lua` | Five lifecycle hooks and explicit system discovery/settings |
| `systems/simulation.lua` | Fixed-step physics/FSM; animation, nodes and camera updates |
| `scripts/content.lua` | Scene composition and cleanup |
| `scripts/builders/` | Level, capsule and imported model construction |
| `scripts/controller/` | Keyboard, mouse and touch input |
| `source/game/characters/` | Shared character: capsule controller, state machine, locomotion, six states and clip blending (also used by the navMeshLab walkers) |
| `scripts/cameras/` | Spring-arm orbit, camera collision and zoom |
| `scripts/ui/` | HUD and optional screen effect as engine UI nodes |
| `assets/` | Converted character, original images, baked environment and shader |

Set `simulation.enabled = false` in `main.lua` to disable its scheduled updates.
This freezes the player FSM, solver, animation and orbit presentation together;
assets and UI remain loaded. Helper scripts are imported explicitly rather than
automatically scheduled. The mandatory empty categories contain no marker files.

## Preserved data and rendering differences

- The FBX skeleton and all six embedded clips were exported with Godot 4.7.1:
  Idle, Walk, Crouch, Fall, Jump and RESET. Run reuses Walk at the source's 3.5x
  speed; no replacement run animation was invented.
- The GLB retains all original bone influences, including the second set of four
  weights, and embeds the three original material textures. Geometry, bind
  matrices and animation channels are reflected together into positive-Z camera
  space. Clip boundaries use the source Animation resource lengths, including
  Jump's 0.6 s duration despite keys outside that resource's playback range.
- Movement uses meters, a 60 Hz fixed simulation, speeds 5/8/3.25 m/s, jump power
  6 m/s and gravity 24.5 m/s². The crouching capsule becomes a sphere when its
  total height reaches its diameter. Feet remain at the same height.
- The 20 m ground mesh uses the original 16x16 gradient texture tiled 10 times.
  The sky is baked from the source environment, with its sky fog contribution
  converted to display color. The HUD and billboard PNGs are copied unchanged.
- The source's retro overlay is hidden; the port keeps it disabled by default.
  F6 enables its pixel grid, jitter, color quantization, vignette and dithering.
- Lighting, fog, billboard fogging and shadow filtering use this engine's renderer,
  so the final shading is an approximation of Godot rather than pixel-identical.
  The source's enabled glow has no equivalent full-screen bloom pass here.
- The infinite Godot collision plane is represented by an invisible 20 km floor;
  the visible plane remains 20 m. Character collisions use the selected rigid-body
  backend with fixed-step velocity control rather than Godot CharacterBody3D.

The supplied game contains no implemented weapons, shooting or audio. Its active
controller is the FSM-based player; the unused older controller/example state are
not alternate runtime modes in this port. Imported asset rights remain those of
the supplied project; see [license notices](licenses.md).

Package the scene with
`python tools/build/packageScene.py source/game/scenes/stareShooter dist/Stare-Shooter.zip`.
It can then run through `katsa . --scene-package dist/Stare-Shooter.zip` on this
engine. Godot and its project files are not runtime dependencies.
