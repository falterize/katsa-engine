-- Actor: runs a script on worker threads, in parallel with the game.
--
--   local actor = world:create('Actor', { script = 'scene://scripts/pathing.lua', workers = 2 })
--   actor:on('progress', function(data) ... end)            -- messages the worker sends
--   actor:request('solve', { from = a, to = b }, function(ok, path) ... end)
--   actor:send('config', settings)                           -- fire and forget
--
-- The script runs in its own Lua state per worker (see source/katsa/thread/worker.lua): it gets
-- the global `Actor` (`Actor.on(topic, fn)`, `Actor.send(topic, data)`), the standard library and
-- the modules listed in `modules`, but never scene nodes, graphics or the engine's globals.
-- Data crosses the boundary as copies (plain tables, strings, numbers, booleans; SharedArray
-- handles for big buffers). Results are delivered on the main thread while the node updates.
local Node = require('./baseNode')
local Pool = require('source.engine.actors.pool')

local Actor = Node.define('Actor', 'Node')
Actor.propertySchema = {
    script = {
        hint = 'Lua file the worker threads run. It registers handlers with Actor.on(topic, fn).',
    },
    workers = {
        default = 1,
        min = 1,
        max = 64,
        hint = 'Worker threads running the script. Requests go to the least busy one.',
    },
    autoStart = { default = true, hint = 'Start the workers when the node is created.' },
    messagesPerFrame = {
        default = 64,
        min = 1,
        max = 4096,
        hint = 'Largest number of results delivered per worker per frame.',
    },
}

-- `scene://`, `shared://` and plain paths: the world's resource scope resolves them, so a scene
-- script folder inside an archive works like any other asset (scene:// maps to the scene's assets).
local function readSource(self, path)
    local resources = self._world and self._world.resources
    if resources and resources.canonical and path:find('://', 1, true) then
        path = resources:canonical(path)
    end
    local data, message = katsa.filesystem.read(path)
    assert(data, message or ('Cannot read ' .. tostring(path)))
    return data
end

function Actor.initialize(self)
    self.script = self.script or ''
    self.workers = self.workers or 1
    self.autoStart = self.autoStart ~= false
    self.messagesPerFrame = self.messagesPerFrame or 64
    self._handlers = {}
end

function Actor.mount(world, properties, parent)
    local node = Node.new('Actor', properties, parent)
    node._world = world
    node:setProcess(true)
    node:onDestroy(function()
        node:stop()
    end)
    if node.autoStart and node.script ~= '' then
        node:start()
    end
    return node
end

-- Starts the worker threads. `source` (Lua text) replaces the file named by `script`.
-- Extra options: `args` (plain table every worker gets as Actor.args), `modules`
-- ({ moduleName = filePath }): modules the script may require, read here so archives work.
--
-- The node tree also calls start() once on the first update (the common node lifecycle hook).
-- Without `source` that call must not restart workers that autoStart already launched: a restart
-- would drop every request issued before the first frame.
function Actor:start(source)
    if self._pool and not source then
        return self
    end
    self:stop()
    local script = source or readSource(self, self.script)
    local modules = {}
    for name, path in pairs(self.modules or {}) do
        modules[name] = readSource(self, path)
    end
    self._pool = Pool.new({
        script = script,
        scriptName = self.script ~= '' and self.script or self.name,
        size = self.workers,
        name = self.name,
        args = self.args,
        modules = modules,
    })
    if not self._pool.threaded then
        -- Not an error: the platform has no worker threads, so the script runs on the main thread
        -- in short slices. Say why once, so a missing native library is easy to spot.
        katsa.log.write(
            'warn',
            ('Actor %s runs on the main thread: %s'):format(tostring(self.name), self._pool.fallbackReason)
        )
    end
    self._pool.onError = function(message, worker)
        self.lastError = message
        local world = self._world
        local journal = world and world.resources and world.resources.store.journal
        if journal then
            journal:record('Actor ' .. tostring(self.name), message, nil, 'actor')
        end
        if self.onError then
            self.onError(message, worker)
        end
    end
    for topic, handler in pairs(self._handlers) do
        self._pool:on(topic, handler)
    end
    return self
end

function Actor:stop(joinMs)
    if self._pool then
        self._pool:destroy(joinMs)
        self._pool = nil
    end
end

function Actor:isRunning()
    return self._pool ~= nil
end

-- False when the platform has no worker threads and the script runs on the main thread.
function Actor:isThreaded()
    return self._pool ~= nil and self._pool.threaded == true
end

-- Why the workers run on the main thread (nil when they are real threads).
function Actor:getFallbackReason()
    return self._pool and self._pool.fallbackReason
end

local function pool(self)
    return assert(self._pool, 'The Actor is not running; call start() or set autoStart')
end

-- Handler for messages the workers send with Actor.send(topic, data): fn(data, workerIndex).
function Actor:on(topic, handler)
    self._handlers[topic] = handler
    if self._pool then
        self._pool:on(topic, handler)
    end
end

function Actor:send(topic, data, worker)
    return pool(self):send(topic, data, worker)
end

function Actor:broadcast(topic, data)
    pool(self):broadcast(topic, data)
end

-- callback(ok, result) runs on the main thread; `ok` is false when the handler failed or is missing.
function Actor:request(topic, data, callback, worker)
    return pool(self):request(topic, data, callback, worker)
end

-- Per worker state and queue depths, for profiling.
function Actor:getStats()
    return self._pool and self._pool:getStats() or {}
end

function Actor:update()
    if self._pool then
        self._pool:update(self.messagesPerFrame)
    end
end

return Actor
