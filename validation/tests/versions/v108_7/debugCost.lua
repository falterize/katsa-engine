-- Diagnostic (not pass/fail): cost of the 3D physics debug view.
--   KATSA_SCENE=physics xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.debug
-- Prints the milliseconds of Physics:drawDebug (Lua side) and of a whole host:draw, with the
-- debug view off and on, plus the number of lines drawn.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame, self.drawMs, self.debugMs = 0, 0, 0
    return self
end

function Tests:update() end

function Tests:draw()
    self.frame = self.frame + 1
    local frame = self.frame
    if frame == 1 then
        self.host = require('source.game.runtime.application').new(
            self.manager,
            os.getenv('KATSA_SCENE') or 'physics'
        )
        self.host:load()
        self.physics = self.host.world.physics
        local original = self.physics.drawDebug
        self.physics.drawDebug = function(...)
            local t = os.clock()
            original(...)
            self.debugMs = self.debugMs + (os.clock() - t) * 1000
        end
    end
    local host = self.host
    host:update(1 / 60, 1 / 60)
    local t = os.clock()
    host:draw()
    local ms = (os.clock() - t) * 1000
    if frame > 60 and frame <= 100 then
        self.drawMs = self.drawMs + ms
    elseif frame == 101 then
        print(('DEBUG off: draw %.1f ms/frame'):format(self.drawMs / 40))
        self.physics.debugEnabled = true
        self.drawMs, self.debugMs = 0, 0
    elseif frame > 120 and frame <= 160 then
        if frame == 150 and os.getenv('KATSA_SHOT') then
            katsa.graphics.captureScreenshot(os.getenv('KATSA_SHOT') .. '/debug.png')
        end
        self.drawMs = self.drawMs + ms
    elseif frame == 161 then
        print(
            ('DEBUG on: draw %.1f ms/frame, drawDebug %.1f ms/frame, bodies %d'):format(
                self.drawMs / 40,
                self.debugMs / 60,
                #self.physics.bodies
            )
        )
        katsa.event.quit()
    end
end

return Tests
