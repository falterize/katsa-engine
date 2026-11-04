local Previous = require('validation.tests.versions.v107.physics2D')
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
    require('validation.tests.versions.v108_6.ribbons').run(self)
    require('validation.tests.versions.v108_6.lighting').run(self)
    require('validation.tests.versions.v108_6.components').run(self)
    require('validation.tests.versions.v108_6.ribbonInterface').run(self)
    require('validation.tests.versions.v108_6.debugPoses').run(self)
    require('validation.tests.versions.v108_6.carAxes').run(self)
    require('validation.tests.versions.v108_6.workspaceSelection').run(self)
    require('validation.tests.versions.v108_6.walkerBlends').run(self)
    require('validation.tests.versions.v108_6.carPoses').run(self)
    require('validation.tests.versions.v108_6.carDrift').run(self)
    print('PASSED ' .. self.count .. ' v108.6 focused checks')
    katsa.event.quit()
end

return Tests
