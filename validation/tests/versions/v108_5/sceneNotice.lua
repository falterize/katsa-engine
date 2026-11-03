-- A scene switch with a notice waits one drawn frame, so "Loading ..." is visible while it builds.
local Manager = require('source.engine.core.sceneManager')

local Module = {}

function Module.run(self)
    local built = 0
    local function factory()
        built = built + 1
        return { update = function() end, draw = function() end }
    end
    local manager = Manager.new()
    manager:switchWithNotice('Loading test...', factory)
    self:check(built == 0 and manager.notice ~= nil, 'the switch is deferred while the notice is pending')

    manager:update(1 / 60, 1 / 60)
    manager:draw()
    self:check(built == 0 and manager.notice ~= nil, 'the first frame draws the notice and does not build')

    manager:update(1 / 60, 1 / 60)
    self:check(built == 1 and manager.notice == nil, 'the second frame builds the scene and clears the notice')
    manager:draw()
    manager:release()
end

return Module
