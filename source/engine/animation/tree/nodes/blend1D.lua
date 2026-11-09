-- Blend1D: clips laid out along one parameter (for example idle / walk / run over `speed`);
-- the two neighbours of the current value share the weight.
local Params = require('../params')

local Blend1D = {}
Blend1D.__index = Blend1D

-- definition: { param = 'speed', points = { { 0, node }, { 2, node }, { 6, node } }, sync = true }
function Blend1D.new(definition, build)
    assert(type(definition.points) == 'table' and #definition.points >= 1, 'Blend1D needs points')
    local points = {}
    for i, point in ipairs(definition.points) do
        points[i] = { at = point[1], node = build(point[2]) }
    end
    table.sort(points, function(a, b)
        return a.at < b.at
    end)
    local children = {}
    for i, point in ipairs(points) do
        children[i] = point.node
    end
    return setmetatable({
        kind = 'Blend1D',
        definition = definition,
        param = definition.param,
        sync = definition.sync ~= false,
        points = points,
        children = children,
    }, Blend1D)
end

function Blend1D:collect(list)
    for _, point in ipairs(self.points) do
        point.node:collect(list)
    end
end

function Blend1D:evaluate(weight, scale, context)
    local value = Params.read(context.tree, self.param)
    local points = self.points
    context:group(self)
    local last = #points
    if value <= points[1].at or last == 1 then
        points[1].node:evaluate(weight, scale, context)
        return
    end
    if value >= points[last].at then
        points[last].node:evaluate(weight, scale, context)
        return
    end
    for i = 1, last - 1 do
        local low, high = points[i], points[i + 1]
        if value >= low.at and value <= high.at then
            local t = (value - low.at) / (high.at - low.at)
            low.node:evaluate(weight * (1 - t), scale, context)
            high.node:evaluate(weight * t, scale, context)
            return
        end
    end
end

function Blend1D:restart()
    for _, point in ipairs(self.points) do
        point.node:restart()
    end
end

function Blend1D:finished()
    return self.points[1].node:finished()
end

return Blend1D
