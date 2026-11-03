-- The shadow options of nodes that draw their own geometry (particles, ribbons): defaults, schema
-- and validation in one place. Mesh3D and the lights keep their own object path, which uses the same
-- names for castShadow, receiveShadow and shadowGroup.
local V = require('../core.validate')

local Shadowing = {}

Shadowing.defaults = {
    castShadow = false,
    receiveShadow = false,
    shadowGroup = 'Default',
    shadowAlphaCutoff = 0.1,
}

local hints = {
    castShadow = 'Writes this node into the shadow maps as alpha tested geometry.',
    receiveShadow = 'Shadows from other objects darken this node. It only shows when the node is lit '
        .. '(see its light settings).',
    shadowGroup = 'Layer group that decides which lights this node casts into and receives from.',
    shadowAlphaCutoff = 'Shadow pass only: texels more transparent than this cast no shadow, so a '
        .. 'soft edge does not produce a hard shadow. Unlike Mesh3D alphaCutoff it never changes how '
        .. 'the node is drawn.',
}

-- Declares the four shared options on a class schema. `extra` adds fields that only matter while
-- shadows are on, so they hide together with the rest.
function Shadowing.describe(class, extra)
    local schema = rawget(class, 'propertySchema') or {}
    class.propertySchema = schema
    for key, hint in pairs(hints) do
        schema[key] = schema[key] or {}
        schema[key].hint = hint
    end
    schema.shadowGroup.visibleWhen = function(node)
        return node.castShadow or node.receiveShadow
    end
    schema.shadowAlphaCutoff.min, schema.shadowAlphaCutoff.max = 0, 1
    schema.shadowAlphaCutoff.visibleWhen = { key = 'castShadow', equals = true }
    for _, key in ipairs(extra or {}) do
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
