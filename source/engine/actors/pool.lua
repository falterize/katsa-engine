-- ActorPool: several workers running the same script, with least-loaded request routing.
--
--   local pool = ActorPool.new({ script = source, size = 4, name = 'path' })
--   pool:request('solve', job, function(ok, result) ... end)   -- goes to the least busy worker
--   pool:broadcast('config', settings)                          -- every worker
--   pool:update()                                               -- every frame: deliver results
--
-- `size` defaults to the CPU count minus one (the main thread keeps a core), at least 1.
local Thread = require('source.katsa.thread')
local InlineWorker = require('./inlineWorker')

local Pool = {}
Pool.__index = Pool

function Pool.defaultSize()
    return math.max(1, Thread.getCpuCount() - 1)
end

-- options: script, size, name, args, modules, scriptName (see katsa.thread.spawn).
function Pool.new(options)
    local size = options.size or Pool.defaultSize()
    assert(size >= 1 and size == math.floor(size), 'Pool size must be a positive integer')
    local self = setmetatable({ workers = {}, outstanding = {}, handlers = {}, nextWorker = 1 }, Pool)
    -- Without worker threads the same contract runs on the calling thread (InlineWorker), so a
    -- scene that uses Actors still works; `threaded` and `fallbackReason` tell which one it got.
    local library, reason = Thread.isSupported(), nil
    if not library then
        local _, why = require('source.katsa.thread.binding').load()
        reason = tostring(why or 'worker threads are unavailable')
    end
    self.threaded, self.fallbackReason = library, reason
    for index = 1, size do
        local spawnOptions = {
            script = options.script,
            scriptName = options.scriptName,
            name = (options.name or 'actor') .. index,
            args = options.args,
            modules = options.modules,
        }
        local worker
        if library then
            worker = Thread.spawn(spawnOptions)
        else
            worker = InlineWorker.new(spawnOptions)
        end
        worker.index = index
        self.outstanding[index] = 0
        worker.onError = function(message)
            self.lastError = message
            if self.onError then
                self.onError(message, index)
            end
        end
        worker.onMessage = function(data, topic)
            local handler = self.handlers[topic]
            if handler then
                handler(data, index, topic)
            end
        end
        self.workers[index] = worker
    end
    return self
end

function Pool:getSize()
    return #self.workers
end

-- Handler for messages workers send with Actor.send(topic, data): fn(data, workerIndex, topic).
function Pool:on(topic, handler)
    self.handlers[topic] = handler
end

local function leastLoaded(self)
    local best, load = 1, math.huge
    local count = #self.workers
    for step = 0, count - 1 do
        local index = (self.nextWorker + step - 1) % count + 1
        if self.workers[index]:isAlive() and self.outstanding[index] < load then
            best, load = index, self.outstanding[index]
        end
    end
    self.nextWorker = best % count + 1
    return best
end

-- Sends to one worker (the least busy one unless `worker` is given).
function Pool:send(topic, data, worker)
    return self.workers[worker or leastLoaded(self)]:send(topic, data)
end

function Pool:broadcast(topic, data)
    for _, worker in ipairs(self.workers) do
        worker:send(topic, data)
    end
end

-- callback(ok, result) runs from update() on the calling thread.
function Pool:request(topic, data, callback, worker)
    local index = worker or leastLoaded(self)
    self.outstanding[index] = self.outstanding[index] + 1
    return self.workers[index]:request(topic, data, function(ok, result)
        self.outstanding[index] = self.outstanding[index] - 1
        if callback then
            callback(ok, result)
        end
    end)
end

-- Delivers results and messages; at most `limit` per worker. Returns how many were delivered.
function Pool:update(limit)
    local count = 0
    for _, worker in ipairs(self.workers) do
        count = count + worker:poll(limit)
    end
    return count
end

function Pool:getPending()
    local total = 0
    for _, count in ipairs(self.outstanding) do
        total = total + count
    end
    return total
end

-- Per worker: state, jobs waiting for an answer, messages sent and received.
function Pool:getStats()
    local stats = {}
    for index, worker in ipairs(self.workers) do
        stats[index] = {
            state = worker:getState(),
            threaded = self.threaded,
            outstanding = self.outstanding[index],
            queued = worker:getPending(true),
            sent = worker.sent,
            received = worker.received,
        }
    end
    return stats
end

-- Stops every worker, waiting up to joinMs (default 0: do not wait) for them to finish.
function Pool:destroy(joinMs)
    for _, worker in ipairs(self.workers) do
        worker:stop(joinMs)
        worker:destroy()
    end
    self.workers = {}
end

return Pool
