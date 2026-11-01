# katsa.net: transport

UDP networking over ENet, built as `katsa_net` (see [building](building.md)). The library
loads only when `katsa.net` is first used, so games without networking do not need it.

```lua
-- Server: open a port. Several hosts on different ports can run in one process.
local host = katsa.net.listen({ port = 7777, maxPeers = 16 })

-- Client
local client = katsa.net.connect({ address = '127.0.0.1', port = 7777, timeout = 5 })

-- Every frame
for event in host:poll() do
    if event.type == 'connect' then
        event.peer:send('welcome', 1)
    elseif event.type == 'receive' then
        print(event.peer.id, event.channel, event.data)
    elseif event.type == 'disconnect' then
        print('left', event.peer.id, event.reason)
    end
end
```

| Channel | Delivery |
| --- | --- |
| 1 | reliable, ordered (events, spawn/despawn, chat) |
| 2 | unreliable, sequenced (state snapshots: stale packets are dropped) |
| 3 | unreliable, unsequenced (fire-and-forget effects) |

`host:poll(seconds)` can wait for the first event. Payloads are Lua strings; payloads larger
than one MTU are fragmented automatically. `peer:getPing()` (ms), `peer:getLoss()` (0..1),
`peer:getAddress()`, `peer:disconnect(reason)`, `host:close()`.

## LAN discovery

```lua
local announcer = katsa.net.lan.announce({ port = 7776, info = 'Room|7777' }) -- server
announcer:update()                                                            -- every frame

local browser = katsa.net.lan.browse({ port = 7776 })                         -- client
browser:refresh()                      -- broadcast a query
local servers = browser:update()       -- { address, port, info, seen }, entries expire after 5 s
```

`info` is an opaque string chosen by the game (the engine layer stores name, game port, player
count). Discovery works on a local network; internet matchmaking needs a separate service.
