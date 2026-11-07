-- Diagnostic (not pass/fail): engine profiler stages of any scene.
--   KATSA_SCENE=lights32 xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.profile
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    local scene = os.getenv('KATSA_SCENE') or 'physics'
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, scene)
        self.host:load()
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    if frame == 40 then
        self.manager.profiler:startRecording({ scene = scene })
    elseif frame == 120 then
        local summary = self.manager.profiler:summary()
        print(('PROFILE %s frame mean %.1f ms'):format(scene, summary.frame.meanMilliseconds or 0))
        for _, stage in ipairs(summary.stages) do
            print(('STAGE %-34s mean %7.2f ms'):format(stage.name, stage.meanMilliseconds or 0))
        end
        katsa.event.quit()
    end
end

return Tests
