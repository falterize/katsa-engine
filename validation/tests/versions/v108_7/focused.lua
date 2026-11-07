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
    require('validation.tests.versions.v108_7.inspector').run(self)
    require('validation.tests.versions.v108_7.lines').run(self)
    require('validation.tests.versions.v108_7.explorerOrder').run(self)
    require('validation.tests.versions.v108_7.curveRange').run(self)
    require('validation.tests.versions.v108_7.rampTimeline').run(self)
    require('validation.tests.versions.v108_7.blendShapes').run(self)
    require('validation.tests.versions.v108_7.pathDebug').run(self)
    require('validation.tests.versions.v108_7.mouse').run(self)
    require('validation.tests.versions.v108_7.windows').run(self)
    require('validation.tests.versions.v108_7.windowsLab').run(self)
    require('validation.tests.versions.v108_7.orbitGlide').run(self)
    print('PASSED ' .. self.count .. ' v108.7 focused checks')
    katsa.event.quit()
end

return Tests
