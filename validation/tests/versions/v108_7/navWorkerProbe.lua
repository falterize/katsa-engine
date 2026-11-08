local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests
function Tests.new(manager) return setmetatable(Previous.new(manager), Tests) end
function Tests:update() end
function Tests:draw()
    if self.done then return end
    self.done = true
    local Pool = require('source.engine.actors.pool')
    local pool = Pool.new({ size = 1, name = 'probe', script = [[
        Actor.on('go', function()
            local Layered = require('source.plugins.pathfinding.layered')
            local nav = Layered.new(10, 10, { levels = 1, cellSize = 2, origin = { 0, 0 } })
            nav:bake(function() return false end, function() return 0 end)
            local path = nav:findPath(1, 0, 1, 15, 0, 15)
            return { n = path and #path.points or -1 }
        end)
    ]] })
    local result
    pool:request('go', {}, function(ok, r) result = { ok, r } end)
    local deadline = katsa.timer.getTime() + 5
    while not result and katsa.timer.getTime() < deadline do pool:update() katsa.timer.sleep(0.005) end
    print('RESULT', result and result[1], result and (type(result[2]) == 'table' and result[2].n or result[2]))
    pool:destroy(200)
    katsa.event.quit()
end
return Tests
