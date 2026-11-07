-- Explorer order under a World: Environment, then World2D, then the other nodes; no category
-- folders exist any more.
local Tree = require('source.engine.editor.tree.traversal')

local Module = {}

local function node(name, class)
    return {
        name = name,
        isA = function(_, query)
            return query == class
        end,
        children = {},
    }
end

function Module.run(self)
    local world = node('World3D', 'World3D')
    world.children = {
        node('Cube', 'Mesh3D'),
        node('Hud', 'World2D'),
        node('Sun', 'DirectionalLight3D'),
        node('Env', 'Environment'),
    }
    local names = {}
    for _, child in ipairs(Tree.children(world)) do
        names[#names + 1] = child.name
    end
    self:check(
        table.concat(names, ',') == 'Env,Hud,Cube,Sun',
        'World children list Environment, World2D, then the rest in authored order'
    )
    self:check(world.children[1].name == 'Cube', 'the authoritative children array is not reordered')
end

return Module
