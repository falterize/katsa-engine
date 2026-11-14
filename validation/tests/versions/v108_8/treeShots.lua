-- Diagnostic: the animationTreeLab pose while walking, squatting and waving (arms only).
--   KATSA_SHOT=tmp/tree xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.8.shots
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

local STEPS = {
    [30] = function(lab) lab:setSpeed(1) end,
    [90] = 'walk',
    [91] = function(lab) lab.tree:set('squat', 1) end,
    [150] = 'squat',
    [151] = function(lab) lab.tree:set('squat', 0) lab:wave() end,
    [166] = 'wave',
    [200] = 'end',
}

function Tests:draw()
    self.frame = (self.frame or 0) + 1
    if self.frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'animationTreeLab')
        self.host:load()
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    local step = STEPS[self.frame]
    local lab = self.host.demo or self.host:getScene().demo
    if type(step) == 'function' then
        step(lab)
    elseif step == 'end' then
        katsa.event.quit()
    elseif step then
        katsa.graphics.captureScreenshot((os.getenv('KATSA_SHOT') or 'tmp/tree') .. '/' .. step .. '.png')
    end
end

return Tests
