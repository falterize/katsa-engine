-- Only the post-processing checks (a quick run of --test-v108.7.post).
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
    require('validation.tests.versions.v108_7.postProcessing').run(self)
    print('PASSED ' .. self.count .. ' post-processing checks')
    katsa.event.quit()
end

return Tests
