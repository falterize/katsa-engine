-- Diagnostic: cost of the first and second Tab (menu) toggles in multiplayerCars, per stage.
-- Run: xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.tab
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update() end

local function timed(label, fn)
    local t = os.clock()
    fn()
    print(('TAB %-22s %.1f ms'):format(label, (os.clock() - t) * 1000))
end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'multiplayerCars')
        self.host:load()
        self.session = self.host.demo
        self.session:host('Tester', 47960 + math.floor(os.clock() * 100) % 9)
    end
    local host, session = self.host, self.session
    if not host then
        return
    end
    local input = host.scene and host.scene.input or session.scene.input
    if frame == 120 or frame == 200 then
        timed('toggleMenu #' .. (frame == 120 and 1 or 2), function()
            input:toggleMenu()
        end)
    end
    local t0 = os.clock()
    host:update(1 / 60, 1 / 60)
    local t1 = os.clock()
    host:draw()
    local t2 = os.clock()
    if (frame >= 120 and frame <= 123) or (frame >= 200 and frame <= 202) then
        print(('TAB frame %d update %.1f ms draw %.1f ms'):format(frame, (t1 - t0) * 1000, (t2 - t1) * 1000))
    end
    if frame == 230 then
        katsa.event.quit()
    end
end

return Tests
