local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(manager)
    return setmetatable({ manager = manager, count = 0 }, Runtime)
end

function Runtime:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v52 ' .. message)
end

function Runtime:update(dt)
    if not self.started then
        self.started = true
        require('source.tests.versions.v52.native')(self)
        print('PASSED ' .. self.count .. ' focused v52 assertions')
        require('source.tests.versions.v51.native')(self)
        self.base = require('source.tests.versions.v48.runtime').new(self.manager, false, true)
    end
    self.base:update(dt)
end

function Runtime:draw()
    if self.base then
        self.base:draw()
    end
end

return Runtime
