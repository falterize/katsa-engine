-- The pathfinding debug view is one section with grid and route switches.
local Plugins = require('source.engine.plugins')

local Module = {}

function Module.run(self)
    local world = require('source.engine.world.world').new(self.manager.resources:scope())
    Plugins.activate(world, { 'pathfinding' })
    local debug = world.environment.debug
    self:check(
        debug.pathfinding and debug.pathfinding.drawPaths == true and not debug.pathfindingPaths,
        'Pathfinding is one debug section with a drawPaths property'
    )
    self:check(#Plugins.debugSections(world) == 1, 'The plugin adds a single debug row')
    local rows = require('source.engine.editor.inspectors.properties').list(debug.pathfinding)
    local names = {}
    for _, row in ipairs(rows) do
        names[#names + 1] = row.key
    end
    self:check(table.concat(names, ',') == 'enabled,drawCells,drawLinks,drawPaths,drawDistance', 'The inspector lists the pathfinding debug settings: ' .. table.concat(names, ','))
    local kinds = {}
    for _, row in ipairs(rows) do
        kinds[row.key] = row.kind
    end
    self:check(kinds.drawCells == 'boolean' and kinds.drawDistance == 'number', 'Debug settings have editable kinds')
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
