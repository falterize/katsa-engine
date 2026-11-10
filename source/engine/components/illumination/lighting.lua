-- Light response of every node that is shaded by scene lights (Mesh3D, Decal3D, particles, ribbons):
-- one number, `lightInfluence`, from 0 (unlit: the node shows its own colour) to 1 (fully lit).
-- This is the only place that knows how it is stored, validated, described and read by renderers.
local V = require('../../core.validate')

local Lighting = {}

-- Accepts the legacy boolean `unlit` that scenes used to author. It is converted once, when the
-- node is created, and never stored: renderers read lightInfluence only.
-- `default` is the class default (1 for meshes, 0 for decals, particles and ribbons).
function Lighting.normalize(node, default)
    -- Plain reads: tracked nodes keep authored values outside rawget.
    local legacy = node.unlit
    if legacy ~= nil then
        if node.lightInfluence == nil then
            node.lightInfluence = legacy and 0 or 1
        end
        node.unlit = nil
    end
    if node.lightInfluence == nil then
        node.lightInfluence = default
    end
    V.number(node.lightInfluence, 'lightInfluence', 0, 1)
end

-- Effective influence for rendering: the authored value, forced to 0 by billboards (canvas
-- surfaces) and by a system layer that turns lighting off.
function Lighting.influence(node)
    if node.canvas ~= nil then
        return 0
    end
    local effects = node._systemEffects
    if effects and not effects.lighting then
        return 0
    end
    return node.lightInfluence or 1
end

function Lighting.unlit(node)
    return Lighting.influence(node) <= 0
end

-- Declares the field on a class schema.
function Lighting.describe(class)
    local schema = rawget(class, 'propertySchema') or {}
    class.propertySchema = schema
    schema.lightInfluence = schema.lightInfluence or {}
    schema.lightInfluence.min, schema.lightInfluence.max = 0, 1
end

return Lighting
