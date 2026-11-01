local Game = require('source.game.runtime.game')
local FrameTimes = require('source.engine.debug.statistics.frameTimes')
local Json = require('vendor.json')

local Comparison = {}
Comparison.__index = Comparison

local function number(name, fallback, minimum, maximum)
    local value = tonumber(os.getenv(name) or fallback)
    assert(value and value >= minimum and value <= maximum, 'Invalid benchmark option: ' .. name)
    return value
end

function Comparison.new(manager)
    io.stdout:setvbuf('no')
    local width = number('KATSA_BENCH_WIDTH', 1920, 320, 7680)
    local height = number('KATSA_BENCH_HEIGHT', 1080, 240, 4320)
    assert(love.window.setMode(width, height, { vsync = 0, depth = 24, stencil = 8 }))
    local self = setmetatable({
        manager = manager,
        warmup = number('KATSA_BENCH_WARMUP', 5, 0, 300),
        duration = number('KATSA_BENCH_SECONDS', 30, 1, 600),
        seed = number('KATSA_BENCH_SEED', 1068, 1, 2147483647),
        order = { 'jolt', 'oimo', 'oimo', 'jolt' },
        index = 0,
        reports = {},
        folder = 'benchmark-logs/physics-' .. os.date('!%Y%m%dT%H%M%SZ') .. '-' .. tostring(
            math.floor(love.timer.getTime() * 1000)
        ),
    }, Comparison)
    assert(love.filesystem.createDirectory(self.folder))
    self:advance()
    return self
end

function Comparison:advance()
    self.index = self.index + 1
    local backend = self.order[self.index]
    if not backend then
        local vendor, device, version, gpu = love.graphics.getRendererInfo()
        local width, height, flags = love.window.getMode()
        assert(love.filesystem.write(
            self.folder .. '/summary.json',
            Json.encode({
                schema = 1,
                engine = require('source.engine.core.version').value,
                scene = 'animationPhysicsLab',
                renderer = { vendor, device, version, gpu },
                window = { width = width, height = height, vsync = flags.vsync, msaa = flags.msaa },
                jit = jit and jit.status() or false,
                seed = self.seed,
                warmupSeconds = self.warmup,
                sampleSeconds = self.duration,
                statsVisible = true,
                runs = self.reports,
            })
        ))
        print('BENCHMARK REPORT ' .. love.filesystem.getSaveDirectory() .. '/' .. self.folder)
        self.done = true
        love.event.quit()
        return
    end
    math.randomseed(self.seed)
    love.math.setRandomSeed(self.seed)
    self.scene =
        assert(self.manager:switch(Game.new, 'animationPhysicsLab', { physicsBackend = backend }))
    self.scene.showStats = true
    local panel = self.scene.statistics.panel
    for index, definition in ipairs(panel.definitions) do
        if definition.id == 'fps' then
            panel:select(index)
        end
    end
    self.elapsed, self.rejected, self.physics, self.solver = 0, 0, 0, 0
    self.frameTimes = FrameTimes.new(300000)
    print('BENCHMARK START', self.index, backend, 'warmup', self.warmup, 'sample', self.duration)
end

function Comparison:update(dt)
    if self.done then
        return
    end
    local previous = self.elapsed
    self.elapsed = self.elapsed + dt
    if previous >= self.warmup then
        if self.manager.focused and love.window.hasFocus() then
            self.frameTimes:add(dt)
            self.physics = self.physics + (self.scene.physics.stats.updateMilliseconds or 0)
            self.solver = self.solver + (self.scene.physics.stats.solverMilliseconds or 0)
        else
            self.rejected = self.rejected + 1
        end
    end
    if self.elapsed < self.warmup + self.duration then
        return
    end
    local report = self.frameTimes:summary()
    report.backend = self.scene.physics.backendName
    report.rejectedFocusFrames = self.rejected
    report.valid = self.rejected == 0
        and report.frames > 0
        and report.frames < self.frameTimes.capacity
    report.physicsMilliseconds = self.physics / math.max(1, report.frames)
    report.solverMilliseconds = self.solver / math.max(1, report.frames)
    report.configuredWorkers = self.scene.physics.stats.workerThreads or 0
    local rows = { 'frame,frame_milliseconds' }
    for index, value in ipairs(self.frameTimes.values) do
        rows[#rows + 1] = string.format('%d,%.9f', index, value)
    end
    assert(
        love.filesystem.write(
            self.folder .. '/run-' .. self.index .. '.csv',
            table.concat(rows, '\n') .. '\n'
        )
    )
    self.reports[#self.reports + 1] = report
    print('BENCHMARK RESULT ' .. Json.encode(report))
    self:advance()
end

function Comparison:draw() end

return Comparison
