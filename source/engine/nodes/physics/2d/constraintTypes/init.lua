-- One module per Constraint2D class. Each returns { name, kind, category }.
local Node = require('source.engine.nodes.core.baseNode')

local modules = {
    'hinge',
    'ballSocket',
    'wheel',
    'prismatic',
    'weld',
    'rope',
    'spring',
    'distance',
    'friction',
    'motor',
    'mouse',
    'pulley',
    'gear',
}

local Types = { list = {}, byName = {} }

function Types.register(base)
    for _, module in ipairs(modules) do
        local definition = require('source.engine.nodes.physics.2d.constraintTypes.' .. module)
        local class = Node.define(definition.name, 'Constraint2D')
        class.kind = definition.kind
        class.category = definition.category
        class.mount = base.mount
        Types.list[#Types.list + 1] = definition.name
        Types.byName[definition.name] = definition
    end
end

return Types
