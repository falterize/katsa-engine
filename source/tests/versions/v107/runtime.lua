local Previous = require('source.tests.versions.v106_8.runtime')
local Physics2D = require('source.tests.versions.v107.physics2D')

local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = Previous.new(manager)
    return setmetatable(self, Tests)
end

function Tests:nodeAuthoring()
    Previous.nodeAuthoring(self)
    local physics = Physics2D.new(self.manager)
    physics:motion()
    physics:collidersAndQueries()
    physics:triggersAndLifetime()
    physics:constraints()
    physics:cameraAndMixed()
    require('source.tests.versions.v107.colliderAuthoring').run(physics)
    require('source.tests.versions.v107.worldClocks').run(physics)
    self.count = self.count + physics.count
end

function Tests:draw()
    if self.done then
        return
    end
    Previous.draw(self)
    print('PASSED ' .. self.count .. ' v107 checks')
end

return Tests
