-- Diagnostic (not pass/fail): the surfaceGallery video panels over time (KATSA_SHOT=<dir>,
-- KATSA_SCENE, default surfaceGallery). Needs the examples project:
--   KATSA_SHOT=/tmp/shots xvfb-run -a luajit tools/dev/katsa.lua ../katsa-engine-examples \
--     --test-v109.videoshots
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

function Tests:draw()
    self.frame = (self.frame or 0) + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.runtime.application').new(
            self.manager,
            os.getenv('KATSA_SCENE') or 'surfaceGallery'
        )
        self.host:load()
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    local dir = os.getenv('KATSA_SHOT') or '/tmp'
    local scene = self.host.instance or self.host.demo
    if frame % 60 == 0 then
        local videos = scene and scene.videos or {}
        local parts = {}
        for _, video in ipairs(videos) do
            parts[#parts + 1] = ('%s %.2f/%s'):format(video.name, video.time, video.status)
        end
        print('VIDEOS frame ' .. frame .. ': ' .. table.concat(parts, ' | '))
    end
    if frame == 90 or frame == 200 or frame == 320 then
        katsa.graphics.captureScreenshot(('%s/video%d.png'):format(dir, frame))
    elseif frame == 330 then
        katsa.event.quit()
    end
end

return Tests
