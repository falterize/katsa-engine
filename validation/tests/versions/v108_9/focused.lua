local Previous = require('validation.tests.versions.v108_8.focused')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    require('validation.tests.versions.v108_9.levelEditorLogic').run(self)
    require('validation.tests.versions.v108_9.levelEditorScene').run(self)
    require('validation.tests.versions.v108_9.fullscreen').run(self)
    print('PASSED ' .. self.count .. ' v108.9 focused checks')
    katsa.event.quit()
end

return Tests
