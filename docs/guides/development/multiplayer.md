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

```lua
local server = Net.Server.new(context, { simulate = { latency = 0.04, jitter = 0.01, loss = 0.05 } })
server:getConditions():set('poor') -- change it while running; every player's link follows
client:getConditions():cycle()     -- off -> good -> mobile -> poor -> terrible
```

`options.simulate` on `Server.new` or `Client.new` (a table or a preset name) delays and drops
packets deterministically (virtual clock, seedable `random`). `latency` and `jitter` are seconds
added in each direction, so the round trip grows by twice the latency; `loss` and `duplicate`
(0..1) apply to the unreliable channels only, reliable packets are delayed but never lost or
reordered. The server shares one `Net.Conditions` object between all its player links.
Presets: `off`, `good`, `mobile`, `poor`, `terrible`. Launch options for any game that reads them
(`Net.Conditions.fromArguments(katsa.launchArguments)`): `--sim-preset <name>`, `--sim-latency <ms>`,
`--sim-jitter <ms>`, `--sim-loss <percent>`, `--sim-duplicate <percent>`.

`client:getPing()` and `player:getPing()` are application-level round trips (`PING`/`PONG` through
the link), so simulated conditions show up in them; the transport's own figure is only the fallback
before the first answer. `validation/tests/katsa/netGame.lua` covers handshake, prediction,
interpolation, remotes, relevance, client authority, capacity and leaving over real loopback UDP;
`v108_7/netConditions.lua` covers the simulation.

## Changing the owner of an entity

`server:setAuthority(object, player)` hands an entity to another player (or to nobody with `nil`);
every client that knows it receives `AUTHORITY`, its `local_` flag flips and
`client.authorityChanged` fires. `server:getAuthority(object)` reads it. A car uses this when the
driver changes.

## Hosting and dedicated servers

A server never shares state with a client by reference. A hosting player runs a server in the
same process (multiplayerCars: `ServerHost`, a physics-only `World3D` of its own) and joins it
through the loopback like everybody else, so host and guests see the same thing, ping included.
A networked scene keeps its client at the scene root and its server in a `server/` folder with its
own `main.lua` and `scripts/`; code both sides need lives in `scripts/shared/`. `settings.lua` names
the entry (`server = 'server.main'`), and `--server` loads it instead of `main.lua`, headless. Nothing
in `server/` or `scripts/shared/` may require client code (views, UI, input, `katsa.graphics`); a
test checks it. The same server runs without a window:

```
luajit tools/dev/katsa.lua . --scene multiplayerCars --server 7777 --name "My arena" --max-players 8
luajit tools/dev/katsa.lua . --scene multiplayerCars --server --sim-preset poor --no-bot
```

A hosting player's game starts that same server as a child process (`katsa.process`, with its own
console window) and joins it with a one-time admin token; see [multiplayerCars](multiplayerCars.md).
`--server` switches the runtime to headless (`Runtime.headless`): SDL's `offscreen` video driver
(no X server or display needed), no drawing or presenting, the frame loop paced at the frame rate
limit (60 by default). The process reads commands from stdin: `help`, `status`, `players`,
`kick <id> [reason]`, `say <text>`, `bots add|clear`, `cars clear`, `net [preset | latency jitter
loss duplicate]`, `quit`. Servers may be started from a script and stopped with Ctrl+C or `quit`.

## Smoothing, stats and validation

- **Delay and extrapolation.** `Client` draws remote entities `interpolationDelay` seconds behind the
  newest snapshot. The delay adapts between about 1.25 snapshot periods and the option value from
  the measured arrival jitter (up quickly, down slowly); `adaptiveDelay = false` fixes it. When the
  newest snapshot is older than the drawn moment the last movement is continued for at most
  `maxExtrapolation` seconds (default 0.06) instead of freezing, then it holds.
- **Stats.** `client:getStats()` returns ping, loss, snapshots per second, newest snapshot age,
  jitter, delay and the number of extrapolated entities (a reused table). A scene shows them in the
  Stats panel by setting `scene.netStats = function() return client:getStats() end`.
- **Validation.** A client-authoritative definition may add `validate(object, newState, elapsed,
  player)`. Return `false, reason` to drop an impossible report; `elapsed` is the time since the
  last accepted state. The server keeps the old state and fires `server.stateRejected(player,
  object, reason)`; the game decides what to do (log, correct, kick).

## Reference game: multiplayerCars

`source/game/scenes/multiplayerCars` combines the pieces: a server-authoritative arena with one car
per player, up to four riders per car (the driver owns the entity; E moves a rider to a nearby car),
a bot that patrols and chases a visible player along an A* route (`pathfinding` plugin), body dents
that are replicated (`nodes/vehicle`), nitro refilled by a rewarded ad (`ads` plugin, validated and
rate limited by the server) and a built-in LAN server list. Controls: WASD/arrows, Shift nitro, E
change car, N watch an ad.

Launch options: `--host [port]` starts a server and joins it, `--connect address[:port]` joins one,
`--server [port]` runs a dedicated headless server, `--name Name` sets the player name, `--sim-*`
degrade the connection (see above); scenes read them from `katsa.launchArguments`. The Tab list
shows every player's ping and has buttons to cycle the simulated network preset of your own
connection and, when you host, of the whole server.
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
