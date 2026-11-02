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
    if self.frame == 1 and os.getenv('KATSA_PROF') then
        require('jit.p').start('Fl1i1', os.getenv('KATSA_PROF'))
    end
    if self.frame == 1 then
        self.scene = assert(self.manager:switch(require('source.game.runtime.game').new, os.getenv('KATSA_SCENE') or 'animationPhysicsLab'))
    end
end

function Tests:draw()
    local dir = os.getenv('KATSA_SHOT')
    if self.frame >= 60 and self.frame < 76 and dir then
        katsa.graphics.captureScreenshot(('%s/f%02d.png'):format(dir, self.frame - 60))
    elseif self.frame == 70 and os.getenv('KATSA_LOADS') then
        local l = self.manager.profiler.loading
        for _, ph in ipairs(l.phases) do print(('LOAD %-40s %7.1f ms'):format(ph.name, ph.ms)) end
        print(('LOAD total %.1f ms'):format(l.total or 0))
    elseif self.frame == 75 and os.getenv('KATSA_PROF') then
        require('jit.p').stop()
    elseif self.frame == 76 and COUNTS then
        local list = {}
        for k, v in pairs(COUNTS) do list[#list + 1] = { k, v } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for i = 1, 12 do if list[i] then print('COUNT', list[i][2], list[i][1]) end end
    elseif self.frame >= 80 then
        print('PASSED probe')
        katsa.event.quit()
    end
end

return Tests
