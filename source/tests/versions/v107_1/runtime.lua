local Previous = require('source.tests.versions.v107.runtime')
local Physics2D = require('source.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:nodeAuthoring()
    Previous.nodeAuthoring(self)
    local physics = Physics2D.new(self.manager)
    require('source.tests.versions.v107_1.authoring').run(physics)
    require('source.tests.versions.v107_1.scaling').run(physics)
    require('source.tests.versions.v107_1.gravity').run(physics)
    require('source.tests.versions.v107_1.flipbookXml').run(physics)
    require('source.tests.versions.v107_1.runner2D').run(physics)
    require('source.tests.versions.v107_1.textEditing').run(physics)
    require('source.tests.versions.v107_1.expansion').run(physics)
    self.count = self.count + physics.count
end

function Tests:draw()
    if self.done then
        return
    end
    Previous.draw(self)
    print('PASSED ' .. self.count .. ' v107.1 checks')
end

return Tests
