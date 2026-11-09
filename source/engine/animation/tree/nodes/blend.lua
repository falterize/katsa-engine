-- Blend: two inputs mixed by `amount` (0 = a, 1 = b).
local Params = require('../params')

local Blend = {}
Blend.__index = Blend

function Blend.new(definition, build)
    return setmetatable({
        kind = 'Blend',
        definition = definition,
        amount = definition.amount or 0,
        sync = definition.sync == true,
        children = { build(definition.a), build(definition.b) },
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
    self.children[1]:evaluate(weight * (1 - t), scale, context)
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
