-- One module per constraint family. Each module returns { name, kind, category, aliases? }.
-- `kind` selects the solver joint; extra class names in `aliases` behave identically and exist
-- so earlier scenes keep loading.
local Node = require('source.engine.nodes.core.baseNode')

local modules = {
    'ballSocket',
    'hinge',
    'slider',
    'cylindrical',
    'universal',
    'ragdoll',
    'weld',
    'generic',
    'rope',
    'spring',
}

local Types = { list = {}, byName = {} }

function Types.register(base)
    local function define(name, kind, definition)
        local class = Node.define(name, 'Constraint3D')
        class.kind = kind
        class.category = definition.category
        class.mount = function(world, properties, parent)
            properties.className = name
            return base.mount(world, properties, parent)
        end
        Types.byName[name] = definition
    end
    for _, module in ipairs(modules) do
        local definition = require('source.engine.nodes.physics.3d.constraintTypes.' .. module)
        define(definition.name, definition.kind, definition)
        Types.list[#Types.list + 1] = definition.name
        for _, alias in ipairs(definition.aliases or {}) do
            define(alias, definition.kind, definition)
        end
    end
end

return Types
