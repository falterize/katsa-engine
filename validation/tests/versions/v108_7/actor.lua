-- Worker threads: messages, requests, shared memory, failures, and the Actor node.
local Thread = require('source.katsa.thread')
local Pool = require('source.engine.actors.pool')

local Module = {}

local function wait(condition, seconds, pump)
    local deadline = katsa.timer.getTime() + (seconds or 5)
    while not condition() and katsa.timer.getTime() < deadline do
        if pump then
            pump()
        end
        katsa.timer.sleep(0.002)
    end
    return condition()
end

function Module.run(self)
    self:check(Thread.isSupported(), 'The thread library loads and finds the Lua C API')
    local worker = Thread.spawn({
        name = 'probe',
        args = { base = 100 },
        script = [[
            Actor.on('add', function(data) return Actor.args.base + data.n end)
            Actor.on('ping', function(data) Actor.send('pong', { n = data.n * 2 }) end)
            Actor.on('boom', function() error('worker failure') end)
        ]],
    })
    local pong, sum, failure
    worker:on('pong', function(data) pong = data.n end)
    worker:send('ping', { n = 21 })
    worker:request('add', { n = 5 }, function(ok, result) sum = ok and result end)
    worker:request('boom', {}, function(ok, message) failure = not ok and message end)
    self:check(wait(function() return pong and sum and failure end, 5, function() worker:poll() end), 'Messages and requests round-trip')
    self:check(pong == 42 and sum == 105, 'The worker computes with its arguments')
    self:check(tostring(failure):find('worker failure', 1, true) ~= nil, 'A failing handler answers with its error')
    worker:stop(2000)
    self:check(wait(function() return not worker:isAlive() end, 3), 'A stop request ends the worker')
    worker:destroy()

    -- Shared memory with atomics: two workers add to one counter and fill disjoint halves.
    local shared = Thread.SharedArray
    local data = shared.new('int32_t', 1000)
    local counter = shared.new('int32_t', 1)
    local script = [[
        local SharedArray = require('source.katsa.thread.sharedArray')
        Actor.on('work', function(job)
            local data = SharedArray.attach(job.data, 'int32_t', job.count)
            local counter = SharedArray.attach(job.counter, 'int32_t', 1)
            for i = job.from, job.to do
                data[i] = i + 1
                counter:add(0, 1)
            end
            return job.to - job.from + 1
        end)
    ]]
    local pool = Pool.new({ script = script, size = 2, name = 'fill' })
    local done = 0
    for half = 0, 1 do
        pool:request('work', {
            data = data:getHandle(), counter = counter:getHandle(), count = 1000,
            from = half * 500, to = half * 500 + 499,
        }, function(ok) if ok then done = done + 1 end end)
    end
    self:check(wait(function() return done == 2 end, 10, function() pool:update() end), 'A pool answers every request')
    local ok = true
    for i = 0, 999 do
        ok = ok and data[i] == i + 1
    end
    self:check(ok and counter[0] == 1000, 'Workers write shared memory in parallel')
    self:check(pool:getSize() == 2 and pool:getPending() == 0, 'The pool reports its size and no pending jobs')
    pool:destroy(2000)
    self:check(data:getReferences() == 1, 'Workers release their references')

    -- A script that fails to start is reported.
    local broken = Thread.spawn({ name = 'broken', script = 'error("bad script")' })
    local message
    broken.onError = function(text) message = text end
    self:check(wait(function() return message end, 3, function() broken:poll() end) and message:find('bad script', 1, true) ~= nil, 'A failing script reports its error')
    broken:destroy()

    -- Images decode on workers and match the main thread's decoder.
    local ImageLoader = require('source.engine.actors.imageLoader')
    local loader = ImageLoader.new(2)
    local path = 'assets/textures/particles/atlas.png'
    local loaded, failed
    loader:load(path, function(ok, image) loaded = ok and image end)
    loader:load('assets/missing.png', function(ok) failed = not ok end)
    self:check(wait(function() return loaded and failed end, 10, function() loader:update() end), 'The image loader answers')
    local reference = katsa.image.newImageData(path)
    self:check(loaded and loaded:getWidth() == reference:getWidth() and loaded:getString() == reference:getString(), 'A worker decodes pixels identical to the main thread')
    self:check(failed, 'A missing file is reported as a failure')
    loader:destroy(2000)

    -- Sounds decode on workers too (WAV here; Ogg Vorbis takes the same path).
    local SoundLoader = require('source.engine.actors.soundLoader')
    local sounds = SoundLoader.new(1)
    local wav = 'assets/audio/effects/stereoChime.wav'
    local heard
    sounds:load(wav, function(ok, sound) heard = ok and sound end)
    self:check(wait(function() return heard end, 10, function() sounds:update() end), 'The sound loader answers')
    local expected = katsa.sound.newSoundData(wav)
    self:check(heard and heard:getString() == expected:getString() and heard:getSampleRate() == expected:getSampleRate() and heard:getChannelCount() == 2, 'A worker decodes samples identical to the main thread')
    sounds:destroy(2000)

    -- The Actor node.
    local world = require('source.engine.world.world').new(self.manager.resources:scope())
    local node = world:create('Actor', { name = 'Brain', workers = 2, autoStart = false })
    local got
    node:on('hello', function(data) got = data.text end)
    node:start([[
        Actor.on('square', function(n) return n * n end)
        Actor.on('greet', function() Actor.send('hello', { text = 'hi' }) end)
    ]])
    local square
    node:request('square', 12, function(_, value) square = value end)
    node:send('greet', {})
    self:check(wait(function() return square and got end, 5, function() node:update() end), 'The Actor node runs a script on workers')
    self:check(square == 144 and got == 'hi', 'The node delivers results and worker messages')
    self:check(#node:getStats() == 2 and node:isRunning(), 'The node reports per-worker stats')
    node:destroy()
    self:check(not node:isRunning(), 'Destroying the node stops its workers')
end

return Module
