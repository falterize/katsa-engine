-- The pathfinding debug view is two independent sections: the grid and the routes.
local Plugins = require('source.engine.plugins')

local Module = {}

function Module.run(self)
    local world = require('source.engine.world.world').new(self.manager.resources:scope())
    Plugins.activate(world, { 'pathfinding' })
    local debug = world.environment.debug
    self:check(
        debug.pathfinding and debug.pathfindingPaths and debug.pathfinding.drawPaths == nil,
        'The grid and the routes are separate debug sections'
    )
    local sections = Plugins.debugSections(world)
    self:check(#sections == 2 and sections[1].drawer ~= sections[2].drawer, 'Each section has its own drawer')
    local Debug = require('source.plugins.pathfinding').Debug
    Debug.setRoute(world, 'bot1', { points = { { 0, 0, 0 } } })
    Debug.setRoute(world, 'bot2', { points = { { 1, 0, 1 } } })
    local count = 0
    for _ in pairs(world.navRoutes) do
        count = count + 1
    end
    self:check(count == 2, 'Several bot routes are kept side by side')
end

return Module
