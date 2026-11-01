local Previous = require('source.tests.versions.v107.physics2D')
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
    require('source.tests.versions.v107_1.authoring').run(self)
    require('source.tests.versions.v107_1.scaling').run(self)
    require('source.tests.versions.v107_1.gravity').run(self)
    require('source.tests.versions.v107_1.flipbookXml').run(self)
    require('source.tests.versions.v107_1.runner2D').run(self)
    require('source.tests.versions.v107_1.textEditing').run(self)
    require('source.tests.versions.v107_1.expansion').run(self)
    print('PASSED ' .. self.count .. ' v107.1 authoring checks')
    katsa.event.quit()
end

return Tests
