-- Blend3: three inputs on one parameter from -1 to 1: -1 is `a`, 0 is `b`, 1 is `c`.
local Params = require('../params')

local Blend3 = {}
Blend3.__index = Blend3

function Blend3.new(definition, build)
    return setmetatable({
        kind = 'Blend3',
        definition = definition,
        amount = definition.amount or 0,
        sync = definition.sync == true,
        children = { build(definition.a), build(definition.b), build(definition.c) },
    }, Blend3)
end

function Blend3:collect(list)
    for _, child in ipairs(self.children) do
        child:collect(list)
    end
end

function Blend3:evaluate(weight, scale, context)
    local t = math.max(-1, math.min(1, Params.read(context.tree, self.amount)))
    context:group(self)
    local children = self.children
    if t < 0 then
        children[1]:evaluate(weight * -t, scale, context)
        children[2]:evaluate(weight * (1 + t), scale, context)
    else
        children[2]:evaluate(weight * (1 - t), scale, context)
        if t > 0 then
            children[3]:evaluate(weight * t, scale, context)
        end
    end
end

function Blend3:restart()
    for _, child in ipairs(self.children) do
        child:restart()
    end
end

function Blend3:finished()
    return self.children[2]:finished()
end

return Blend3
