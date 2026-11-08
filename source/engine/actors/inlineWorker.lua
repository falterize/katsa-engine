-- InlineWorker: the same worker contract as katsa.thread, run on the calling thread. ActorPool
-- falls back to it when the platform has no worker threads (missing native library, a host that
-- does not export the Lua C API), so scenes and plugins that use Actors still work, only without
-- parallelism: jobs run from poll() in slices of at most SLICE_MS, so a long job spreads over
-- frames instead of freezing one. Data still crosses as copies, so a script behaves the same here
-- as on a thread.
local buffer = require('string.buffer')

local InlineWorker = {}
InlineWorker.__index = InlineWorker

local SLICE_MS = 4

local function copy(value)
    return value == nil and nil or buffer.decode(buffer.encode({ value })) [1]
end

-- options: script (Lua text), scriptName, name, args, modules ({ name = source }).
function InlineWorker.new(options)
    local self = setmetatable({
        name = options.name or 'actor',
        handlers = {},
        replies = {},
        queue = {},
        outbox = {},
        nextId = 0,
        sent = 0,
        received = 0,
        state = 'running',
        inline = true,
    }, InlineWorker)
    local worker = self
    local actorHandlers = {}
    local loaded = {}
    local sources = options.modules or {}
    local env
    local Actor = {
        handlers = actorHandlers,
        manual = false,
        args = copy(options.args) or {},
        on = function(topic, fn)
            actorHandlers[topic] = fn
        end,
        send = function(topic, data)
            worker.outbox[#worker.outbox + 1] = { topic = topic, data = copy(data) }
        end,
        stopped = function()
            return worker.stopRequested == true
        end,
        sleep = function() end,
        poll = function()
            return false
        end,
    }
    env = setmetatable({ Actor = Actor }, { __index = _G })
    -- Modules listed in `modules` load into this worker only; everything else is the normal require.
    env.require = function(name)
        if sources[name] then
            if loaded[name] == nil then
                local chunk = assert(loadstring(sources[name], '=' .. name))
                setfenv(chunk, env)
                loaded[name] = chunk() or true
            end
            return loaded[name]
        end
        return require(name)
    end
    self.actorHandlers = actorHandlers
    local chunk, message = loadstring(options.script, '=' .. (options.scriptName or self.name))
    if chunk then
        setfenv(chunk, env)
        local ok, failure = pcall(chunk)
        if not ok then
            chunk, message = nil, failure
        end
    end
    if not chunk then
        self.state, self.failure = 'failed', tostring(message)
    end
    return self
end

function InlineWorker:on(topic, handler)
    self.handlers[topic] = handler
end

function InlineWorker:send(topic, data)
    self.sent = self.sent + 1
    self.queue[#self.queue + 1] = { topic = topic, data = copy(data) }
    return true
end

function InlineWorker:request(topic, data, callback)
    self.nextId = self.nextId + 1
    local id = self.nextId
    self.replies[id] = callback or false
    self.sent = self.sent + 1
    self.queue[#self.queue + 1] = { topic = topic, data = copy(data), id = id }
    return id
end

local function reply(self, id, ok, value)
    local callback = self.replies[id]
    self.replies[id] = nil
    if callback then
        callback(ok, value)
    end
end

-- Runs queued jobs for up to SLICE_MS (at least one), then delivers the worker's messages.
function InlineWorker:poll(limit)
    if self.state == 'destroyed' then
        return 0
    end
    local count = 0
    if self.state == 'failed' then
        if not self.failureReported then
            self.failureReported = true
            for id in pairs(self.replies) do
                reply(self, id, false, self.failure)
            end
            if self.onError then
                self.onError(self.failure)
            end
        end
        return 0
    end
    local started = os.clock()
    local limitJobs = limit or 64
    while #self.queue > 0 and count < limitJobs do
        local job = table.remove(self.queue, 1)
        local handler = self.actorHandlers[job.topic]
        if handler then
            local ok, result = pcall(handler, job.data)
            if job.id then
                reply(self, job.id, ok, ok and copy(result) or tostring(result))
            elseif not ok and self.onError then
                self.onError(tostring(result))
            end
        elseif job.id then
            reply(self, job.id, false, 'No handler for ' .. tostring(job.topic))
        end
        count = count + 1
        self.received = self.received + 1
        if (os.clock() - started) * 1000 >= SLICE_MS then
            break
        end
    end
    local outbox = self.outbox
    if #outbox > 0 then
        self.outbox = {}
        for _, message in ipairs(outbox) do
            local handler = self.handlers[message.topic] or self.onMessage
            if handler then
                handler(message.data, message.topic)
            end
        end
    end
    return count
end

function InlineWorker:getState()
    return self.state
end

function InlineWorker:getError()
    return self.failure
end

function InlineWorker:getPending(inbox)
    return inbox == false and #self.outbox or #self.queue
end

function InlineWorker:isAlive()
    return self.state == 'running'
end

function InlineWorker:stop()
    self.stopRequested = true
    return true
end

function InlineWorker:destroy()
    self.state = 'destroyed'
    self.queue, self.outbox = {}, {}
end

return InlineWorker
