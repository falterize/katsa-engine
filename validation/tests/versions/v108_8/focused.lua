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
    require('validation.tests.versions.v108_8.animationNodes').run(self)
    require('validation.tests.versions.v108_8.additivePose').run(self)
    require('validation.tests.versions.v108_8.clipPlayback').run(self)
    require('validation.tests.versions.v108_8.graphNodes').run(self)
    require('validation.tests.versions.v108_8.realClips').run(self)
    print('PASSED ' .. self.count .. ' v108.8 focused checks')
    katsa.event.quit()
end

return Tests
