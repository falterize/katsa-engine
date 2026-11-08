-- Diagnostic: screenshots of the menu with its tag list and chooser (KATSA_SHOT=<dir>).
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

function Tests:draw()
    self.frame = (self.frame or 0) + 1
    if self.frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, 'menu')
        self.host:load()
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    local dir = os.getenv('KATSA_SHOT') or '/tmp'
    if self.frame == 5 then
        katsa.graphics.captureScreenshot(dir .. '/menuList.png')
    elseif self.frame == 6 then
        self.host.setTags({ physics = true })
        self.host.tagChooser.visible = true
    elseif self.frame == 10 then
        katsa.graphics.captureScreenshot(dir .. '/menuTags.png')
    elseif self.frame == 12 then
        katsa.event.quit()
    end
end

return Tests
