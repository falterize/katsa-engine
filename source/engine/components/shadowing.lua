-- The shadow options of every node that casts or receives shadows (Mesh3D, lights, particles,
-- ribbons): defaults, schema and validation in one place. Nodes that draw procedural geometry
-- (particles, ribbons) also have shadowAlphaCutoff; meshes use their material's alphaCutoff.
local V = require('../core.validate')

local Shadowing = {}

Shadowing.defaults = {
    castShadow = false,
    receiveShadow = false,
    shadowGroup = 'Default',
    shadowAlphaCutoff = 0.1,
}

-- Fills the class defaults of an object created without them (`defaults` is a table such as
-- { castShadow = true, receiveShadow = true }) and checks the booleans.
function Shadowing.normalize(node, defaults)
    for key, value in pairs(defaults) do
        if node[key] == nil then
            node[key] = value
        end
        assert(type(node[key]) == 'boolean', key .. ' must be a boolean')
    end
end

-- Declares the shared options on a class schema. Options:
--   receive = false   the class cannot receive shadows (lights)
--   cutoff = false    the class has no shadowAlphaCutoff (meshes and lights)
--   extra = { ... }   fields that only matter while the node casts shadows
function Shadowing.describe(class, options)
    options = options or {}
    local schema = rawget(class, 'propertySchema') or {}
    class.propertySchema = schema
    for key in pairs(Shadowing.defaults) do
        if (key ~= 'receiveShadow' or options.receive ~= false)
            and (key ~= 'shadowAlphaCutoff' or options.cutoff ~= false)
        then
            schema[key] = schema[key] or {}
        end
    end
    schema.shadowGroup.visibleWhen = function(node)
        return node.castShadow or node.receiveShadow
    end
    if options.cutoff ~= false then
        schema.shadowAlphaCutoff.min, schema.shadowAlphaCutoff.max = 0, 1
        schema.shadowAlphaCutoff.visibleWhen = { key = 'castShadow', equals = true }
    end
    for _, key in ipairs(options.extra or {}) do
        schema[key] = schema[key] or {}
        schema[key].visibleWhen = { key = 'castShadow', equals = true }
    end
end

function Shadowing.validate(node, name)
    assert(type(node.castShadow) == 'boolean', name .. '.castShadow must be a boolean')
    assert(type(node.receiveShadow) == 'boolean', name .. '.receiveShadow must be a boolean')
    V.number(node.shadowAlphaCutoff, name .. '.shadowAlphaCutoff', 0, 1)
end

return Shadowing
