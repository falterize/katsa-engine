-- Diagnostic (not pass/fail): multiplayerCars hosted with bots at a world TimeScale
-- (KATSA_TIMESCALE, default 5). Prints frame time percentiles and the stages with the worst spikes.
--   KATSA_TIMESCALE=5 xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.timescale
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

local SCALE = tonumber(os.getenv('KATSA_TIMESCALE') or '5')
local BOTS = tonumber(os.getenv('KATSA_BOTS') or '6')

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

function Tests:draw()
    self.frame = self.frame + 1
    if self.frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load()
        self.session = self.host.demo
        self.session:host('Tester', 47960 + math.floor(os.clock() * 100) % 9)
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    local server = self.session.server
    if not (server and server.hostPlayer) then
        return
    end
    self.start = self.start or self.frame
    local t = self.frame - self.start
    if t == 10 then
        for _ = 1, BOTS do
            server:hostCommand(server.hostPlayer, 'spawnBot')
        end
        self.host.world.root.timeScale = SCALE
    elseif t == 60 then
        self.manager.profiler:startRecording({ scene = 'multiplayerCars' })
    elseif t == 360 then
        local summary = self.manager.profiler:summary()
        local f = summary.frame
        print(('TIMESCALE %g  bots %d  frame mean %.1f  p95 %.1f  p99 %.1f  worst %.1f ms'):format(
            SCALE, BOTS, f.meanMilliseconds, f.p95Milliseconds, f.p99Milliseconds, f.worstMilliseconds))
        table.sort(summary.stages, function(a, b)
            return (a.peakMilliseconds or 0) > (b.peakMilliseconds or 0)
        end)
        for i = 1, math.min(8, #summary.stages) do
            local stage = summary.stages[i]
            print(('STAGE %-30s mean %6.2f  p95 %6.2f  peak %7.2f ms'):format(stage.name,
                stage.meanMilliseconds, stage.p95Milliseconds, stage.peakMilliseconds))
        end
        print('PASSED probe')
        katsa.event.quit()
    end
end

return Tests
