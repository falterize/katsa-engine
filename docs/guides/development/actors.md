# Actors and worker threads

LuaJIT runs one Lua state per thread, so Katsa gets parallelism the same way Roblox Actors do: a script
runs in **its own state on its own OS thread**, and threads exchange **copies of data**, never live
objects. Use it for work that is heavy and independent of the scene: pathfinding, procedural
generation, mesh and noise baking, AI planning, compression, bulk simulation.

Measured in the Linux sandbox (2 cores): four 4e7-iteration jobs take 3.06 s on 1 worker and 1.74 s on
2 workers. Real speed-up depends on the machine; the main thread keeps rendering while workers run.

## The Actor node

```lua
local brain = world:create('Actor', {
    name = 'Brain',
    script = 'scene://worker/pathing.lua',   -- file the workers run (scene:// is the scene's assets folder)
    workers = 2,                              -- threads; requests go to the least busy one
})
brain:on('progress', function(data, worker) print(data.percent) end)
brain:request('solve', { from = a, to = b }, function(ok, path)
    if ok then follow(path) else warn(path) end   -- on failure `path` is the error text
end)
brain:send('config', { agility = 3 })             -- fire and forget
brain:broadcast('reload', {})                      -- every worker
```

Inspector properties: `script`, `workers`, `autoStart` (start when created), `messagesPerFrame`
(results delivered per worker per frame). `Actor:start(source?)`, `stop(joinMs?)`, `isRunning()`,
`getStats()` (state, outstanding requests, queue depth, messages sent/received per worker).
Extra fields set on the node at creation: `args` (a plain table every worker receives as
`Actor.args`) and `modules` (`{ name = file }`, modules the worker may `require`; they are read on the
main thread so archives work). A failing worker reports through the world's error journal and
`node.onError(message, worker)`.

Results are delivered on the main thread while the node updates (so a paused world, whose delta is
zero, delivers nothing until it runs again).

## Example scene

`actorLab` (category Performance) is the smallest complete example: a spinning cube, a heavy job
(count the primes below 1.8 million, split into 8 ranges) and three buttons. "Run on the main
thread" freezes the screen while it counts; "Run on workers (Actor)" sends the ranges with
`actor:request(...)` and the cube keeps spinning while the answers arrive. The worker code is
`assets/worker/primes.lua`, the node and callbacks are in `scripts/content.lua`. "Send a ping
message" shows `actor:send` and a worker answering with `Actor.send`. The `multiplayerCars` host
HUD line also shows the bot route searches running on a worker (`RemotePlanner`).

## The worker script

The worker has the standard library, `ffi`, `string.buffer`, the preloaded `modules`, relative
`require` and one global, `Actor`. It has **no** window, graphics, audio, scene nodes or `katsa` API.

```lua
-- pathing.lua
local Grid = require('grid')                    -- listed in `modules`
Actor.on('solve', function(job)                 -- return value answers brain:request(...)
    local path = Grid.search(job.from, job.to)
    Actor.send('progress', { percent = 100 })   -- plain message to brain:on('progress')
    return path
end)
```

`Actor.on(topic, fn)`, `Actor.send(topic, data)`, `Actor.args`, `Actor.stopped()`, `Actor.sleep(ms)`,
`Actor.poll(timeoutMs)`. By default the worker handles messages until it is stopped. For your own
loop set `Actor.manual = true` and call `Actor.poll(0)` between slices of work, ending when
`Actor.stopped()` is true. A handler error answers a request with `ok = false`; for a plain message it
arrives as the owner's `$error` message and `onError`.

Data that crosses is serialized with `string.buffer`: tables of numbers, strings, booleans and
nested tables (no functions, userdata or cycles).

## Shared memory

Copying a million-cell grid on every request is wasteful; share it instead.

```lua
local SharedArray = katsa.thread.SharedArray
local grid = SharedArray.new('uint8_t', width * height)   -- 0-based; grid.count; grid.data
brain:broadcast('grid', { handle = grid:getHandle(), type = 'uint8_t', count = grid.count })

-- worker
Actor.on('grid', function(data)
    SharedArray = require('source.katsa.thread.sharedArray')
    GRID = SharedArray.attach(data.handle, data.type, data.count)   -- no copy
end)
```

Blocks are reference counted (garbage collection and `release()` let go). There is no implicit locking:
let threads write disjoint ranges, or use the atomics on `int32_t` arrays (`add`, `load`, `store`,
`compareAndSet`) for counters, flags and ticket locks. Read a block while another thread writes
it only if you can tolerate seeing partial results.

## Pools and the low-level API

`source/engine/actors/pool.lua` (`ActorPool.new{ script, size, name, args, modules }`) is what the node
uses: `request`, `send`, `broadcast`, `on`, `update`, `getStats`, `destroy`. `katsa.thread.spawn` is
one worker with `send`, `request`, `on`, `poll`, `stop`, `destroy`, `getState`, `getError`.
`katsa.thread.isSupported()` tells whether the native library and the Lua C API are available.

## Loading images off the main thread

```lua
local loader = require('source.engine.actors.imageLoader').new()   -- up to 4 workers
loader:load('assets/hero.png', function(ok, image) ... end)         -- image is a katsa.image ImageData
-- every frame: loader:update()
```

The file is read on the calling thread (archives and the save folder work); the decoding runs on a
worker and returns through shared memory. Upload the ImageData to a texture in the callback.

`SoundLoader` (`source/engine/actors/soundLoader.lua`) does the same for sounds: `load(path, cb)` gives a
`katsa.sound` SoundData. It matters most for large WAV files, which are decoded sample by sample in
Lua, and for long Ogg Vorbis tracks.

## Native layer and platforms

`native/src/threads/` (pthreads / Win32 threads, condition variables, atomics; `threads.h` lists the
files and the thread-safety rules) builds to `libkatsa_threads.so` / `katsa_threads.dll` /
`libkatsa_threads.dylib` with `tools/native/build.py <target> threads`.
It does not link Lua: at start-up the process hands it `luaL_newstate`, `lua_pcall` and the few other
entry points through `ffi.C`, so **the host executable must export the Lua C API** (the dev
`luajit` does; the shipped `katsa_host` links LuaJIT statically with `-rdynamic` on Linux, and on
Windows the host must export the `lua*` symbols). Where the symbols are missing `isSupported()` is
false and `spawn` raises a clear error; nothing else in the engine depends on it.

Rules that keep it fast and safe: send **jobs** (coarse messages) rather than thousands of tiny
ones; a worker is cooperative, so a handler must return in reasonable time for `stop` to take effect
(an unresponsive worker is detached and frees itself when it ends); never touch scene nodes from a
worker, compute with plain data and apply the result in the main-thread callback.

After changing `native/src/threads`, run `sh validation/native/threadsStress.sh` on Linux: it
builds a stress test with ThreadSanitizer and AddressSanitizer (hundreds of actors destroyed at
random moments) and must report `races=0` and no ASan errors.
