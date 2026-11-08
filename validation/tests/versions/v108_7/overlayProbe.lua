-- Diagnostic (not pass/fail): Screen UI cost with the debug overlays closed and open.
--   KATSA_SCENE=physics xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.overlays
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

local PHASES = {
    { 'closed', nil },
    { 'stats F3', 'f3' },
    { 'stats + F4', 'f4' },
    { 'stats + F4 + console F1', 'f1' },
}
local LENGTH = 90

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

local function stage(summary, name)
    for _, s in ipairs(summary.stages) do
        if s.name == name then
            return s.meanMilliseconds, s.p95Milliseconds
        end
    end
    return 0, 0
end

function Tests:draw()
    self.frame = self.frame + 1
    local scene = os.getenv('KATSA_SCENE') or 'physics'
    if self.frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, scene)
        self.host:load()
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    local index = math.floor((self.frame - 30) / LENGTH) + 1
    local offset = (self.frame - 30) % LENGTH
    if self.frame < 30 then
        return
    end
    local phase = PHASES[index]
    if not phase then
        print('PASSED probe')
        katsa.event.quit()
        return
    end
    if offset == 0 then
        if phase[2] then
            self.host:keypressed(phase[2])
        end
    elseif offset == 20 then
        self.manager.profiler:startRecording({ scene = scene })
    elseif offset == LENGTH - 1 then
        local summary = self.manager.profiler:summary()
        local mean, p95 = stage(summary, 'Screen UI')
        print(('OVERLAY %-26s Screen UI mean %6.2f p95 %6.2f ms   frame %6.2f ms'):format(
            phase[1], mean, p95, summary.frame.meanMilliseconds))
    end
end

return Tests
