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
    require('validation.tests.versions.v108_5.frontFace').run(self)
    require('validation.tests.versions.v108_5.ik').run(self)
    require('validation.tests.versions.v108_5.ikNode').run(self)
    require('validation.tests.versions.v108_5.uiStylerFiles').run(self)
    require('validation.tests.versions.v108_5.scrollMotion').run(self)
    require('validation.tests.versions.v108_5.carMesh').run(self)
    require('validation.tests.versions.v108_5.hoverCoalesce').run(self)
    require('validation.tests.versions.v108_5.consoleRows').run(self)
    require('validation.tests.versions.v108_5.menuAndInterrupt').run(self)
    require('validation.tests.versions.v108_5.netThrottle').run(self)
    require('validation.tests.versions.v108_5.packaging').run(self)
    require('validation.tests.versions.v108_5.touchZoom').run(self)
    print('PASSED ' .. self.count .. ' v108.5 focused checks')
    katsa.event.quit()
end

return Tests
