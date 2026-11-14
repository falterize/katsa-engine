-- Add3: `base` with `plus` added for a positive `amount` (0..1) and `minus` for a negative one
-- (-1..0), both additive like Add2. Typical use: lean left / lean right over a walk.
local Params = require('../params')
local Layers = require('../layers')

local Add3 = {}
Add3.__index = Add3

-- definition: { base = node, minus = node, plus = node, amount = 'lean', filter = {...} }
function Add3.new(definition, build)
    local base, minus, plus = build(definition.base), build(definition.minus), build(definition.plus)
    for _, child in ipairs({ minus, plus }) do
        Layers.apply(child, {
            additive = true,
            reference = definition.reference,
            filter = definition.filter,
            children = definition.filterChildren,
        })
    end
    return setmetatable({
        kind = 'Add3',
        definition = definition,
        amount = definition.amount or 0,
        sync = definition.sync == true,
        children = { base, minus, plus },
    }, Add3)
end

function Add3:collect(list)
    for _, child in ipairs(self.children) do
        child:collect(list)
    end
end

function Add3:evaluate(weight, scale, context)
    local amount = math.max(-1, math.min(1, Params.read(context.tree, self.amount, 0)))
    context:group(self)
    self.children[1]:evaluate(weight, scale, context)
    if amount < 0 then
        self.children[2]:evaluate(weight * -amount, scale, context)
    elseif amount > 0 then
        self.children[3]:evaluate(weight * amount, scale, context)
    end
end

function Add3:restart()
    for _, child in ipairs(self.children) do
        child:restart()
    end
end

function Add3:finished()
    return self.children[1]:finished()
end

return Add3
