# multiplayerCars: the networked sample scene

`source/game/scenes/multiplayerCars` is a complete LAN game built on the engine's networking: host
or join, walk, drive, chat, talk, kick, a bot that chases players, and a damage model.

## Controls

| Input | Action |
| --- | --- |
| WASD / left stick | move or drive; Space jump; Shift run / nitro |
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
`{ x, y, z, nx, ny, nz, depth }` (depth capped at 0.55 m). `view/carMesh.lua` builds the car as
lofted hull and cabin sections; `Body.deform` moves each vertex along the dent normals with a
smooth falloff, so the lattice stays continuous. Dents are serialised with the entity, so everybody
(including late joiners) sees the same shape. The driver's client reports impacts
(`remote('impact')`); the server validates them and broadcasts the new dent list.

Tuning lives in `scripts/game/physicsCar.lua` (`gravityScale`, `stiffness`, `damping`, grip) and
`nodes/vehicle/model.lua` (`maxSpeed`, `acceleration`, `brake`, `drag`).

## The bot and the car park

The bot (`scripts/game/bot.lua`) patrols and chases the nearest reachable human car on a
`NavMap` baked from the real colliders (see [plugins](plugins.md)); the arena has a two-floor car
park (deck, curbs, columns and a ramp, tagged `navFloor = 2`). It aims only at waypoints on its
own floor, slows for sharp turns and on the deck, and re-plans after reversing out of a wall.
*Path debug* in the HUD draws its route; *Pathfinding debug* in the debug menu draws the whole map.
