local Previous = require('validation.tests.versions.v108_9.focused')
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
    require('validation.tests.versions.v109.projects').run(self)
    require('validation.tests.versions.v109.phoneConsole').run(self)
    print('PASSED ' .. self.count .. ' v109 focused checks')
    katsa.event.quit()
end

return Tests
