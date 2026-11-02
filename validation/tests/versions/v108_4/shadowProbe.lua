-- Diagnostic: captures consecutive frames of animationPhysicsLab (KATSA_SHOT=<dir>).
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        self.scene = assert(self.manager:switch(require('source.game.runtime.game').new, os.getenv('KATSA_SCENE') or 'animationPhysicsLab'))
    end
end

function Tests:draw()
    local dir = os.getenv('KATSA_SHOT')
    if self.frame >= 60 and self.frame < 76 and dir then
        katsa.graphics.captureScreenshot(('%s/f%02d.png'):format(dir, self.frame - 60))
    elseif self.frame >= 80 then
        print('PASSED probe')
        katsa.event.quit()
    end
end

return Tests
