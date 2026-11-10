-- Ranking number shared by nodes that compete for one role (the lights that count as "the sun",
-- the detectors that answer one click). Higher goes first; equal priorities fall back to the
-- consumer's own order. One definition of the rule: a finite number, default 0.
local V = require('../../core.validate')

local Priority = {}

-- Fills the default when the field is absent, then validates it.
function Priority.normalize(node, default)
    if node.priority == nil then
        node.priority = default or 0
    end
    V.number(node.priority, 'priority')
end

-- True when `a` ranks before `b`, false when `b` ranks before `a`, nil on a tie (the caller
-- decides: distance, creation order ...).
function Priority.higher(a, b)
    local first, second = a.priority or 0, b.priority or 0
    if first ~= second then
        return first > second
    end
end

-- Declares the field on a class schema.
function Priority.describe(class)
    local schema = rawget(class, 'propertySchema') or {}
    class.propertySchema = schema
    schema.priority = schema.priority or {}
end

return Priority
