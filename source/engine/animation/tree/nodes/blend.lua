-- Blend: two inputs mixed by `amount` (0 = a, 1 = b). With a `filter` (bone names, or
-- bone = weight; `filterChildren = true` adds descendants) only those bones take part in the mix and
-- every other bone plays `a` alone: `b` becomes a layer above `a`.
local Params = require('../params')
local Layers = require('../layers')

local Blend = {}
Blend.__index = Blend

function Blend.new(definition, build)
    local a, b = build(definition.a), build(definition.b)
    if definition.filter then
        Layers.apply(b, { boost = 1, filter = definition.filter, children = definition.filterChildren })
    end
    return setmetatable({
        kind = 'Blend',
        definition = definition,
        amount = definition.amount or 0,
        sync = definition.sync == true,
        filtered = definition.filter ~= nil,
        children = { a, b },
    }, Blend)
end

function Blend:collect(list)
    for _, child in ipairs(self.children) do
        child:collect(list)
    end
end

function Blend:evaluate(weight, scale, context)
    local t = math.max(0, math.min(1, Params.read(context.tree, self.amount)))
    context:group(self)
    self.children[1]:evaluate(self.filtered and weight or weight * (1 - t), scale, context)
    self.children[2]:evaluate(weight * t, scale, context)
end

function Blend:restart()
    for _, child in ipairs(self.children) do
        child:restart()
    end
end

function Blend:finished()
    return self.children[1]:finished()
end

return Blend
