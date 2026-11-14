-- Add2: `base` plus `add` scaled by `amount`. The clips of `add` are additive: their difference to
-- a reference pose (first frame, or the rest pose with `reference = 'rest'`) is added on top.
-- `filter` (bone names, or bone = weight) limits the bones, `filterChildren = true` adds their
-- descendants. Typical use: a lean or a breathing clip over any locomotion.
local Params = require('../params')
local Layers = require('../layers')

local Add2 = {}
Add2.__index = Add2

-- definition: { base = node, add = node, amount = 'lean', filter = { 'Spine' } }
function Add2.new(definition, build)
    local base, add = build(definition.base), build(definition.add)
    Layers.apply(add, {
        additive = true,
        reference = definition.reference,
        filter = definition.filter,
        children = definition.filterChildren,
    })
    return setmetatable({
        kind = 'Add2',
        definition = definition,
        amount = definition.amount or 1,
        sync = definition.sync == true,
        children = { base, add },
    }, Add2)
end

function Add2:collect(list)
    for _, child in ipairs(self.children) do
        child:collect(list)
    end
end

function Add2:evaluate(weight, scale, context)
    local amount = math.max(0, math.min(1, Params.read(context.tree, self.amount, 1)))
    context:group(self)
    self.children[1]:evaluate(weight, scale, context)
    if amount > 0 then
        self.children[2]:evaluate(weight * amount, scale, context)
    end
end

function Add2:restart()
    for _, child in ipairs(self.children) do
        child:restart()
    end
end

function Add2:finished()
    return self.children[1]:finished()
end

return Add2
