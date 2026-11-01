-- Plugin loader: manifests, lazy loading, dependency order and the pathfinding add-on.
local Plugins = require('source.engine.plugins')

local Module = {}

function Module.run(self)
    local names = Plugins.names()
    local found = false
    for _, name in ipairs(names) do
        found = found or name == 'pathfinding'
    end
    self:check(found, 'Plugin loader lists the pathfinding add-on')
    self:check(Plugins.manifest('pathfinding').title == 'Pathfinding', 'Plugin manifest is readable')
    self:check(not Plugins.has('missingPlugin'), 'Unknown plugins are reported as absent')
    self:check(not pcall(Plugins.require, 'missingPlugin'), 'Requiring an unknown plugin fails')
    local api = Plugins.require('pathfinding')
    self:check(api.Grid and api.Graph and Plugins.require('pathfinding') == api, 'Plugins load once')
    local grid = api.Grid.new(6, 6)
    grid:fill(3, 1, 3, 5, true)
    self:check(grid:findPath(0.5, 0.5, 5.5, 0.5) ~= nil, 'Plugin API finds a route around a wall')
end

return Module
