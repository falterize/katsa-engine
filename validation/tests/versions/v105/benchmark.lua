-- CPU-only solver benchmark: identical scene, fixed steps, no quality changes.
local Physics = require('source.engine.physics')
local World = require('source.engine.world.world')

local Benchmark = {}
Benchmark.__index = Benchmark

function Benchmark.new(manager)
    io.stdout:setvbuf('no')
    return setmetatable({ manager = manager }, Benchmark)
end

function Benchmark:update() end

function Benchmark:draw()
    if self.done then
        return
    end
    self.done = true
    local workers = tonumber(os.getenv('KATSA_BENCH_THREADS') or '4')
    local count = tonumber(os.getenv('KATSA_BENCH_BODIES') or '576')
    local samples, solves = {}, {}
    local totalWorkerCallbacks, native, nativeSamples = 0, 0, 0
    for repetition = 1, 3 do
        local resources = self.manager.resources:scope()
        local world = World.new(resources)
        world.physics = Physics.new({ backend = 'jolt', workerThreads = workers })
        world:create(
            'Body3D',
            { bodyType = 'Static', position = { 0, -10, 0 }, size = { 2000, 20, 2000 } }
        )
        for index = 0, count - 1 do
            local node = world:create('Body3D', {
                name = 'BenchmarkBox' .. index,
                position = {
                    (index % 24) * 24 - 288,
                    10 + math.floor(index / 144) * 19.8,
                    (math.floor(index / 24) % 6) * 24 - 72,
                },
                size = { 20, 20, 20 },
                autoSleep = false,
            })
            node.physics:set({ autoSleep = false })
        end
        collectgarbage('collect')
        for step = 1, 180 do
            local started = katsa.timer.getTime()
            world:updateNodes(1 / 60)
            world.physics:update(1 / 60)
            if step > 60 then
                samples[#samples + 1] = (katsa.timer.getTime() - started) * 1000
                solves[#solves + 1] = world.physics.stats.solverMilliseconds
                native = native + (world.physics.stats.nativeSolverMilliseconds or 0)
                nativeSamples = nativeSamples + 1
            end
        end
        totalWorkerCallbacks = totalWorkerCallbacks
            + (world.physics.stats.workerContactCallbacks or 0)
        world:release()
        resources:release()
    end
    table.sort(samples)
    local update, solver = 0, 0
    for index, value in ipairs(samples) do
        update = update + value
        solver = solver + solves[index]
    end
    print('workers,bodies,samples,update_mean_ms,update_p95_ms,solver_mean_ms,worker_callbacks')
    print(
        string.format(
            '%d,%d,%d,%.4f,%.4f,%.4f,%d',
            workers,
            count,
            #samples,
            update / #samples,
            samples[math.ceil(#samples * 0.95)],
            solver / #samples,
            totalWorkerCallbacks
        )
    )
    print('native_solver_mean_ms', native / nativeSamples)
    print('V105 BENCHMARK COMPLETE')
    katsa.event.quit()
end

return Benchmark
