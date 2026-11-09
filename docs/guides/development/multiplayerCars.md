# multiplayerCars: the networked sample scene

`source/game/scenes/multiplayerCars` is a complete LAN game built on the engine's networking: host
or join, walk, drive, chat, talk, kick, a bot that chases players, and a damage model.

## Controls

| Input | Action |
| --- | --- |
| WASD / left stick | move or drive; Space jump on foot, **handbrake / drift** in a car (phones: hold the *Drift* button); Shift run / nitro |
| mouse | the cursor is captured and turns the camera until **Tab** (or the *Menu* button) frees it |
| wheel / pinch / `+` `-` | camera zoom (the wheel scrolls UI under the cursor instead) |
| Q | shift-lock (camera-relative facing) |
| E | enter / leave a car; N watch an ad for nitro |
| Enter | open the chat box (Enter sends, Esc cancels) |
| V (hold) | push-to-talk voice, desktop only |
| Tab | free the cursor and show the player list; the host can **Kick** players |

The controller and camera are the StareShooter ones (`scripts/controller/input.lua`,
`scripts/cameras/orbit.lua`); driving and seating states were added on top. Driving widens the
FOV with speed (`speedFov`).

## Chat, voice, kick, names

* `server:remote('chat')` is rate limited (5 lines / 4 s), trimmed and 200 characters at most; the
  broadcast carries `{ id, name, host, text }` and the client shows `[HOST] Name: text`.
* Voice: the microphone (`katsa.audio.openCapture`) is read while V is down, compressed with
  μ-law (`engine/audio/muLaw.lua`, 12 kHz, one byte per sample) and sent in 80 ms packets over an
  **unreliable** remote (`remote:unreliable()`); the server relays packets to the others, who
  decode them into `katsa.audio.newQueueSource` placed on the speaker (3D, distance fade). The
  HUD shows who is speaking.
* Names are unique ignoring case: the server rejects a second *"ann"* with *The name "ann" is
  already taken* (`Server` option `uniqueNames = false` turns it off).
* Host tools (Tab panel, host only, checked on the server): Spawn car / Spawn bot appear six metres in front
  of the host, Clear bots removes every bot, Clear cars removes every car (players are put out first).
  Esc opens the pause menu with `keepTime`, so the hosted game keeps simulating.
* Kick: only the host (`GameServer.hostPlayer`) may call `remote('kick')`; the target receives
  *Kicked by the host* as the disconnect reason and may join again.

## Console and events

Server events are logged as `[server] ...` through `katsa.log.log(text, 'multiplayerCars')` and
passed to `GameServer.onEvent`: joins, leaves, spawns, sitting down, getting out, kicks, chat and
lost wheels. Clients log `[client] Name joined/left` and `[chat] ...`. Open the console (Debug)
to read them.

## Cars and damage

`nodes/vehicle/damage.lua` decides wheel loss. Every wheel has health 1. An impact slower than
`MIN_SPEED` (5 m/s) does nothing; otherwise `strength = (speed - 5) / TOUGHNESS` (16) and each
wheel within `REACH` (1.5 m) of the impact point loses `strength * (1.2 - distance / 1.5)` health;
at 0 the wheel is torn off. `detached` is a bitmask (bit *i-1* = wheel *i*) replicated through the
`dents` remote and stored in the entity args, so late joiners see it. A hit anywhere on the body
(front, side, rear, roof) counts because impacts carry a 3D position in car space. Detached wheels
skip suspension and cost 15 % top speed each; they become rolling debris on every client
(`view/carView.lua:shedWheel`).

The body shape changes through `nodes/vehicle/deformation.lua`: up to 24 dents
`{ x, y, z, nx, ny, nz, depth }` (depth capped at 0.7 m). `view/carModel.lua` turns the Duke 69
(`assets/models/duke69.glb`) into nodes: Body, Hood and Trunkdoor are the tinted paint, every
other panel and light owns a dentable copy of its vertices, the interior, steering wheel and
suspension are rigid, and the four wheels are separate pivots. `CarModel.deform` moves each vertex
along the dent normals with a falloff, adds a deterministic crumple and pulls the metal toward the
dent centre; creased triangles are flat shaded. Parts a dent cannot reach are skipped
(`Deformation:touches`). Without the GLB the car falls back to the lofted `view/carMesh.lua` hull. Dents are serialised with the entity, so everybody
(including late joiners) sees the same shape. The driver's client reports impacts
(`remote('impact')`); the server validates them and broadcasts the new dent list.

Tuning lives in `scripts/game/physicsCar.lua` (`gravityScale`, `stiffness`, `damping`, grip) and
`nodes/vehicle/model.lua` (`maxSpeed`, `acceleration`, `brake`, `drag`).

## The bot and the car park

The bot (`scripts/game/bot.lua`) patrols and chases the nearest reachable human car on a
`NavMap3D` baked from the real colliders (see [plugins](plugins.md)); the arena has a two-floor car
park (deck, curbs, columns and a ramp, tagged `navFloor = 2`). It aims only at waypoints on its
own floor, slows for sharp turns and on the deck, and re-plans after reversing out of a wall.
`Environment.debug.pathfinding` (editor or F4 *Pathfinding*) is the only switch: it draws the whole map and the bot route (fed through `Pathfinding.Debug.setRoute`).


## Model, materials and import

`tools/import/fbxDump.c` (ufbx) dumps the FBX, `tools/import/fbxCarToGlb.py` builds the GLB (car
space, +z forward, wheels renamed `Wheel_FL/FR/RL/RR` and centred on their hubs) and
`tools/import/carMaps.py` writes the PBR maps in `assets/textures/duke`: colour, a normal map from
each height map, roughness and metalness. `carModel.lua` gives each part group a
`SurfaceAppearance3D` with every map it has; paint uses scalar roughness and metalness (its UVs are
an atlas, not a tile) and the glass is a Blend material with low alpha and low roughness.

## Drift, skid marks and automatic flip

Holding Space (or the *Drift* button) in a car is a handbrake: the rear tires lock (braking against
the direction of travel), sideways grip drops and the nose swings further than the steering asks.
`PhysicsCar` writes the replicated `drift` field (0..1, from the slide speed and the locked
tires); `view/skid.lua` draws rear-wheel smoke (`ParticleEmitter3D`, world space) and dark flat
`Trail3D` skid marks (dual mode, world-space edge nodes, a segment per slide that ages out) on
every machine from it.

A car on its side or roof rights itself (`PhysicsCar:autoFlip`: a torque about the forward axis
after 0.7 s plus a lift). Only falling below the arena (`y < -30`) respawns a car.
