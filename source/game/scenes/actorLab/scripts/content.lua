local Mesh = require('source.engine.composition.mesh')

-- The Actor node in practice. A cube spins on the main thread; two buttons run the same heavy job
-- (count the primes below LIMIT, split into CHUNKS ranges):
--   * "Main thread": the job runs inside one frame. The cube freezes and the longest frame shows it.
--   * "Workers (Actor)": the ranges are `request`ed from an Actor node. The cube keeps spinning
--     while workers count, and the answers arrive through callbacks on the main thread.
-- The worker code is assets/worker/primes.lua. The numbers on screen are measured, not estimated.
local Lab = {}
Lab.__index = Lab

local LIMIT = 1800000
local CHUNKS = 8

local function countPrimes(from, to)
    local count = 0
    for n = math.max(2, from), to do
        local prime = true
        for d = 2, math.floor(math.sqrt(n)) do
            if n % d == 0 then
                prime = false
                break
            end
        end
        if prime then
            count = count + 1
        end
    end
    return count
end

function Lab.new(scene)
    local self = setmetatable({ scene = scene, time = 0, longest = 0 }, Lab)
    local world = scene.world
    world.environment.debug.gizmos.enabled = false
    world.environment.sky.enabled = false
    world.environment.fog.enabled = false
    world.environment.ambient = { 70, 78, 96 }
    world:create('DirectionalLight3D', {
        name = 'Sun',
        rotation = { 55, 30, 0 },
        color = { 255, 238, 210 },
        brightness = 1.1,
    })
    self.cube = Mesh.create(world, {
        name = 'Heartbeat',
        kind = 'cube',
        size = { 3, 3, 3 },
        color = { 0.9, 0.5, 0.2, 1 },
        position = { 0, 0, 0 },
    })
    -- The Actor node: `workers` threads run the script; requests go to the least busy one.
    self.actor = world:create('Actor', {
        name = 'Counter',
        script = 'scene://worker/primes.lua',
        workers = 2,
        args = { name = 'counter' },
    })
    self.actor:on('pong', function(data, worker)
        self.lastPong = ('worker %d answered %s'):format(worker, tostring(data.echo))
    end)
    scene.camera.position = { 0, 2, 9 }
    scene.camera.rotation = { -8, 180, 0 }
    return self
end

local function chunks()
    local list, size = {}, math.floor(LIMIT / CHUNKS)
    for index = 1, CHUNKS do
        list[index] = { from = (index - 1) * size + 1, to = index == CHUNKS and LIMIT or index * size }
    end
    return list
end

function Lab:startMain()
    if self.job then
        return
    end
    local started = katsa.timer.getTime()
    local total = 0
    for _, range in ipairs(chunks()) do
        total = total + countPrimes(range.from, range.to)
    end
    -- The whole job ran inside this one frame, so no frame could be drawn meanwhile.
    self.result = ('Main thread: %d primes, %.0f ms, the screen was frozen the whole time'):format(
        total,
        (katsa.timer.getTime() - started) * 1000
    )
end

function Lab:startWorkers()
    if self.job then
        return
    end
    local job = { started = katsa.timer.getTime(), total = 0, left = CHUNKS }
    self.job = job
    self.longest = 0
    for _, range in ipairs(chunks()) do
        -- request(topic, data, callback): the callback runs here, on the main thread, from update.
        self.actor:request('count', range, function(ok, value)
            if not ok then
                self.result = 'Worker failed: ' .. tostring(value)
                self.job = nil
                return
            end
            job.total = job.total + value
            job.left = job.left - 1
            if job.left == 0 then
                self.result = ('Workers: %d primes, %.0f ms, longest frame %.0f ms (the cube kept spinning)'):format(
                    job.total,
                    (katsa.timer.getTime() - job.started) * 1000,
                    self.longest * 1000
                )
                self.job = nil
            end
        end)
    end
end

function Lab:ping()
    -- send(topic, data) needs no answer; the worker replies with its own message.
    self.actor:send('ping', { value = math.floor(self.time * 10) })
end

function Lab:update(dt)
    self.time = self.time + dt
    self.cube.rotation = { self.time * 40, self.time * 70, 0 }
    if self.job then
        self.longest = math.max(self.longest, dt)
    end
    self.scene.world:updateNodes(dt)
    if self.status then
        local text = self.result or 'Press a button'
        if self.job then
            text = ('Workers: %d of %d ranges done...'):format(CHUNKS - self.job.left, CHUNKS)
        end
        if self.lastPong then
            text = text .. '\n' .. self.lastPong
        end
        -- Rewritten only when it changes: a label that changes every frame costs a UI relayout.
        if text ~= self.status.text then
            self.status.text = text
        end
    end
end

return Lab
