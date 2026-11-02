# Multiplayer (engine networking)

`source/engine/net` runs an **authoritative server** and **predicting clients** over
[katsa.net](../katsa/net.md). The server owns the game state; clients send input and mirror
what the server replicates. Everything is plain Lua tables, so it works with any node type.

```lua
local Net = require('source.engine.net')

-- Shared by server and client: one definition per kind of replicated object.
local function avatar()
    return {
        fields = { 'position:vec2', 'angle:angle' },          -- replicated state ("name:type")
        create = function(context, args, netId) return world:create('Body2D', args) end,
        destroy = function(object) object:destroy() end,
        simulate = function(object, input, dt) move(object, input, dt) end, -- input-driven step
    }
end

-- Server
local server = Net.Server.new(world, { port = 7777, tickRate = 60, snapshotRate = 20 })
server:define('Avatar', avatar())
server.playerAdded:connect(function(player)
    server:spawn('Avatar', { x = 100, y = 100 }, player)       -- player = authority
end)
server:start()
server:advertise({ name = 'My room', game = 'Cars' })          -- LAN list (optional)
-- every frame: server:update(dt)

-- Client
local client = Net.Client.new(world, { address = '127.0.0.1', port = 7777, name = 'Ann' })
client:define('Avatar', avatar())
client.inputProvider = function() return { x = axisX(), y = axisY() } end
client:connect()
-- every frame: client:update(dt)
```

## How it works

| Piece | Behavior |
| --- | --- |
| Tick | The server simulates at a fixed `tickRate` (60 Hz) and sends snapshots at `snapshotRate` (20 Hz). |
| Authority | `spawn(kind, args, player)`: that player's input drives the object through `simulate`. Without a player the server owns it. |
| Prediction | The authority client runs `simulate` immediately with its own input and keeps unacknowledged inputs. |
| Reconciliation | Each snapshot carries the last input the server applied. The client takes the server state and replays the remaining inputs. |
| Interpolation | Other objects are shown 100 ms in the past (`interpolationDelay`), blended between snapshots by field type. |
| Loss | Snapshots are unreliable; each carries full state of changed objects and everything repeats once a second. Inputs are sent three times. |
| Client authority | `clientAuthoritative = true`: the owner sends the state (for cosmetic or non-critical objects); the server accepts it only from that player. |
| Relevance | `relevant(player, object)` limits who receives an object; it is re-evaluated at every snapshot. |

Field types: `f32`, `f64`, `u8`, `u16`, `i32`, `bool`, `string`, `angle` (degrees, 16-bit), `vec2`,
`vec3`. `simulate` must produce the same result on server and client (use the same function).

## Remote events and functions

```lua
server:remote('Chat'):onServer(function(player, text)           -- client -> server
    server:remote('Chat'):fireAll(player.name, text)             -- server -> clients
end)
client:remote('Chat'):onClient(function(author, text) end)
client:remote('Chat'):fireServer('hello')

server:remote('Buy'):onRequest(function(player, item) return true, 'ok' end)
client:remote('Buy'):request(function(success, status) end, 'nitro')
```

Arguments may be nil, booleans, numbers, strings and tables with string keys or arrays. Never trust
client arguments: validate them in the server handler.

## Joining, leaving and lists

`server.playerAdded` / `playerRemoved`, `client.connected` / `disconnected` / `playerJoined` /
`playerLeft` / `entitySpawned` / `entityRemoved` are signals (`signal:connect(fn)` returns an
unsubscribe function). A joining client first receives every existing object. A leaving player's
objects are despawned unless their definition sets `despawnWithAuthority = false`. A full server
rejects with `client.rejection == 'Server is full'`.

`Net.browse()` lists LAN servers advertised with `server:advertise`: entries have `name`,
`address`, `port`, `players`, `maxPlayers`, `game`. Call `refresh()` periodically and `update()`
each frame.

## Testing with bad networks

`options.simulate = { latency = 0.04, jitter = 0.01, loss = 0.05 }` on `Server.new` or
`Client.new` delays and drops packets deterministically (virtual clock, seedable `random`).
`validation/tests/katsa/netGame.lua` covers handshake, prediction, interpolation, remotes,
relevance, client authority, capacity and leaving over real loopback UDP.

## Changing the owner of an entity

`server:setAuthority(object, player)` hands an entity to another player (or to nobody with `nil`);
every client that knows it receives `AUTHORITY`, its `local_` flag flips and
`client.authorityChanged` fires. `server:getAuthority(object)` reads it. A car uses this when the
driver changes.

## Reference game: multiplayerCars

`source/game/scenes/multiplayerCars` combines the pieces: a server-authoritative arena with one car
per player, up to four riders per car (the driver owns the entity; E moves a rider to a nearby car),
a bot that patrols and chases a visible player along an A* route (`pathfinding` plugin), body dents
that are replicated (`nodes/vehicle`), nitro refilled by a rewarded ad (`ads` plugin, validated and
rate limited by the server) and a built-in LAN server list. Controls: WASD/arrows, Shift nitro, E
change car, N watch an ad.

Launch options: `--host [port]` starts a server and joins it, `--connect address[:port]` joins one,
`--name Name` sets the player name (scenes read them from `katsa.launchArguments`).
Tests: `validation/tests/katsa/carsGame.lua` (rules over loopback UDP) and `--test-v108.4.cars`
(the scene on the real renderer; `KATSA_CARS_SHOT=<dir>` saves screenshots).

## Kicks, names and unreliable remotes

```lua
-- Server: disconnect a player and tell them why. The client's `disconnected` signal receives the
-- text; the player may join again.
server:kick(player, 'Kicked by the host: spamming')

-- Names are unique among connected players, ignoring case. A duplicate is rejected with
-- 'The name "Ann" is already taken'. Disable with Net.Server.new(world, { uniqueNames = false }).

-- Best-effort remotes for streams (voice): no retransmission, may drop or reorder.
server:remote('voice'):unreliable():onServer(function(player, bytes)
    server:remote('voice'):fireOthers(player, player.id, bytes)
end)
client:remote('voice'):unreliable():onClient(function(speakerId, bytes) play(bytes) end)
client:remote('voice'):fireServer(bytes)
```

Both ends must mark the remote `unreliable()`; reliable remotes (the default) are ordered and
retransmitted. See [multiplayerCars](multiplayerCars.md) for chat, voice, host-only kick requests
(`remote:onRequest`) and console events.
