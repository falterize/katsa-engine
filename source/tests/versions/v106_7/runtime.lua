local Previous = require('source.tests.versions.v106_6.runtime')

local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = Previous.new(manager)
    love.errorhandler = function(message)
        print('FAILED v106.7 ' .. tostring(message))
        os.exit(1)
    end
    return setmetatable(self, Tests)
end

function Tests:check(value, label)
    assert(value, label)
    self.count = self.count + 1
    print('PASS v106.7', label)
end

function Tests:nodeAuthoring()
    Previous.nodeAuthoring(self)
    require('source.tests.versions.v106_7.menuIdle').run(self)
    require('source.tests.versions.v106_7.skinAndMenu').run(self)
end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self:layout()
    self:scenePackages()
    self:allScenes()
    self:systems()
    self:interfaces()
    self:privateNodes()
    self:portableScenes()
    self:nodeAuthoring()
    require('source.tests.versions.v106_6.stareShooter').run(self)
    self:check(#self.manager.journal.entries == 0, 'No runtime journal errors')
    print('PASSED ' .. self.count .. ' v106.7 checks')
    love.event.quit()
end

return Tests
