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
    require('source.tests.versions.v108_1.audioModules').run(self)
    require('source.tests.versions.v108_1.shaderScopes').run(self)
    print('PASSED ' .. self.count .. ' v108.1 focused checks')
    love.event.quit()
end

return Tests
