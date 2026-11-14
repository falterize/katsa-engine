-- Sub2: `base` minus `sub` scaled by `amount`: the difference of the clips of `sub` to a reference
-- pose (first frame, or the rest pose with `reference = 'rest'`) is removed from the pose. The
-- opposite of Add2; `filter` and `filterChildren` limit the bones. Typical use: take a breathing
-- or a lean out of a clip that already has it.
local Params = require('../params')
local Layers = require('../layers')

local Sub2 = {}
Sub2.__index = Sub2

-- definition: { base = node, sub = node, amount = 'lean', filter = { 'Spine' } }
function Sub2.new(definition, build)
    local base, sub = build(definition.base), build(definition.sub)
    Layers.apply(sub, {
        additive = true,
        subtract = true,
        reference = definition.reference,
        filter = definition.filter,
        children = definition.filterChildren,
    })
    return setmetatable({
        kind = 'Sub2',
        definition = definition,
        amount = definition.amount or 1,
        sync = definition.sync == true,
        children = { base, sub },
    }, Sub2)
end

function Sub2:collect(list)
    for _, child in ipairs(self.children) do
        child:collect(list)
    end
end

function Sub2:evaluate(weight, scale, context)
    local amount = math.max(0, math.min(1, Params.read(context.tree, self.amount, 1)))
    context:group(self)
    self.children[1]:evaluate(weight, scale, context)
    if amount > 0 then
        self.children[2]:evaluate(weight * amount, scale, context)
    end
end

function Sub2:restart()
    for _, child in ipairs(self.children) do
        child:restart()
    end
end

function Sub2:finished()
    return self.children[1]:finished()
end

return Sub2
