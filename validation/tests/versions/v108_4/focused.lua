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
    require('validation.tests.versions.v108_4.componentTypes').run(self)
    require('validation.tests.versions.v108_4.console').run(self)
    require('validation.tests.versions.v108_4.plugins').run(self)
    require('validation.tests.versions.v108_4.clone').run(self)
    require('validation.tests.versions.v108_4.flyingAudio').run(self)
    require('validation.tests.versions.v108_4.layerAffects3D').run(self)
    require('validation.tests.versions.v108_4.meshCollider').run(self)
    print('PASSED ' .. self.count .. ' v108.4 focused checks')
    katsa.event.quit()
end

return Tests
