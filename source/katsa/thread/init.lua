-- katsa.thread: OS threads that each run their own Lua state ("actors"), plus shared memory.
--
-- Threads exchange serialized messages and shared blocks only; no Lua value is shared. The engine's
-- `Actor` node (source/engine/nodes/core/actor.lua) and `ActorPool` are built on this module.
--
--   local worker = katsa.thread.spawn({ script = 'return ...source...', name = 'pathing' })
--   worker:on('done', function(data) ... end)
--   worker:request('solve', { n = 1e6 }, function(ok, result) ... end)
--   -- every frame:
--   worker:poll()
--
-- A worker script gets the global `Actor` (see worker.lua). When the native library or the Lua C
-- API is unavailable `katsa.thread.isSupported()` is false and `spawn` raises a clear error.
local ffi = require('ffi')
local Binding = require('./binding')
local SharedArray = require('./sharedArray')

local buffer = require('string.buffer')

local Thread = { SharedArray = SharedArray }
Thread.__index = Thread

local STATES = { [0] = 'starting', 'running', 'finished', 'failed' }

local prelude
local function preludeSource()
    if prelude then
        return prelude
    end
    local path = 'source/katsa/thread/worker.lua'
    local data
    if katsa and katsa.filesystem then
        data = katsa.filesystem.read(path)
    end
    if not data then
        local file = assert(io.open(path, 'rb'), 'Cannot read ' .. path)
        data = file:read('*a')
        file:close()
    end
    prelude = data
    return prelude
end

-- Native library folders of this state, so workers find the same libraries.
local function directories()
    local list = {}
    for _, directory in ipairs(require('source.katsa.core.native').directories) do
        list[#list + 1] = string.format('%q', directory)
    end
    return '{' .. table.concat(list, ',') .. '}'
end

function Thread.isSupported()
    return Binding.load() ~= nil
end

function Thread.getCpuCount()
    local library = Binding.load()
    return library and library.kt_cpu_count() or 1
end

-- options: script (Lua source text, required), name, scriptName (chunk name for errors),
-- args (plain table passed to the script), modules ({ moduleName = sourceText }: preloaded so the
-- worker can require them, also from archives).
function Thread.spawn(options)
    assert(type(options) == 'table' and type(options.script) == 'string', 'spawn needs a script')
    local library, message = Binding.load()
    if not library then
        error('Worker threads are unavailable: ' .. tostring(message), 2)
    end
    local Native = require('source.katsa.core.native')
    local name = options.name or 'actor'
    local self = setmetatable({
        name = name,
        library = library,
        handlers = {},
        replies = {},
        nextId = 0,
        sent = 0,
        received = 0,
    }, Thread)
    local header = string.format(
        'KATSA_LIB=%q KATSA_CDEF=%q KATSA_PATH=%q KATSA_CPATH=%q KATSA_ARGS=%q '
            .. 'KATSA_SCRIPT=%q KATSA_SCRIPT_NAME=%q KATSA_LIBDIRS=%s KATSA_MODULES={',
        Native.paths.Threads,
        Binding.cdef,
        package.path,
        package.cpath,
        options.args and buffer.encode(options.args) or '',
        options.script,
        options.scriptName or name,
        directories()
    )
    local parts = { header }
    for module, source in pairs(options.modules or {}) do
        parts[#parts + 1] = string.format('[%q]=%q,', module, source)
    end
    parts[#parts + 1] = '}\n'
    local bootstrap = table.concat(parts) .. preludeSource()
    self.native = library.kt_spawn(name, bootstrap, #bootstrap)
    if self.native == nil then
        error('Could not start the worker thread', 2)
    end
    return self
end

local function encode(envelope)
    return buffer.encode(envelope)
end

-- Fire and forget: handlers registered with Actor.on(topic) receive `data` in the worker.
function Thread:send(topic, data)
    assert(self.native, 'The actor was destroyed')
    local bytes = encode({ topic = topic, data = data })
    self.sent = self.sent + 1
    return self.library.kt_send(self.native, 1, bytes, #bytes) ~= 0
end

-- Asks the worker's handler for `topic`; callback(ok, result) runs from poll().
function Thread:request(topic, data, callback)
    assert(self.native, 'The actor was destroyed')
    self.nextId = self.nextId + 1
    local id = self.nextId
    self.replies[id] = callback or false
    local bytes = encode({ topic = topic, data = data, id = id })
    self.sent = self.sent + 1
    self.library.kt_send(self.native, 1, bytes, #bytes)
    return id
end

-- Handler for messages the worker sends with Actor.send(topic, data).
function Thread:on(topic, handler)
    self.handlers[topic] = handler
end

local dataPointer = ffi.new('const void*[1]')
local lengthPointer = ffi.new('size_t[1]')

-- Delivers up to `limit` (default 64) pending messages and replies on the calling thread, then
-- reports a worker failure once through `onError(message)`. Returns the number delivered.
function Thread:poll(limit)
    if not self.native then
        return 0
    end
    local library, count = self.library, 0
    for _ = 1, limit or 64 do
        local message = library.kt_recv(self.native, 0, 0, dataPointer, lengthPointer)
        if message == nil then
            break
        end
        local envelope = buffer.decode(ffi.string(dataPointer[0], lengthPointer[0]))
        library.kt_release(message)
        count = count + 1
        self.received = self.received + 1
        if envelope.reply then
            local callback = self.replies[envelope.reply]
            self.replies[envelope.reply] = nil
            if callback then
                if envelope.error then
                    callback(false, envelope.error)
                else
                    callback(true, envelope.data)
                end
            end
        elseif envelope.topic == '$error' and not self.handlers['$error'] then
            if self.onError then
                self.onError(envelope.data)
            end
        else
            local handler = self.handlers[envelope.topic] or self.onMessage
            if handler then
                handler(envelope.data, envelope.topic)
            end
        end
    end
    if not self.failureReported and library.kt_state(self.native) == 3 then
        self.failureReported = true
        local message = ffi.string(library.kt_error(self.native))
        for id, callback in pairs(self.replies) do
            self.replies[id] = nil
            if callback then
                callback(false, message)
            end
        end
        if self.onError then
            self.onError(message)
        end
    end
    return count
end

function Thread:getState()
    return self.native and STATES[self.library.kt_state(self.native)] or 'destroyed'
end

function Thread:getError()
    if self.native and self.library.kt_state(self.native) == 3 then
        return ffi.string(self.library.kt_error(self.native))
    end
end

-- Messages waiting for the worker, and (inbox = false) for this side.
function Thread:getPending(inbox)
    return self.native and self.library.kt_pending(self.native, inbox == false and 0 or 1) or 0
end

function Thread:isAlive()
    return self.native ~= nil and self.library.kt_exited(self.native) == 0
end

-- Asks the worker to finish (Actor.stopped() turns true); waits up to joinMs for it.
function Thread:stop(joinMs)
    if self.native then
        self.library.kt_request_stop(self.native)
        if joinMs then
            return self.library.kt_join(self.native, joinMs) ~= 0
        end
    end
    return false
end

-- Stops and releases the thread. A worker stuck in a long computation is detached and frees
-- itself when it ends; nothing here blocks.
function Thread:destroy()
    if self.native then
        self.library.kt_destroy(self.native)
        self.native = nil
    end
end

return Thread
