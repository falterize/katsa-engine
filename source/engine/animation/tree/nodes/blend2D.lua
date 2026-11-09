-- Blend2D: clips laid out on a plane (for example strafe and walk directions over `x`, `y`).
-- Weights use gradient-band interpolation: a clip's weight falls to zero at every other clip,
-- so the result is smooth, local, and needs no triangulation.
local Params = require('../params')

local Blend2D = {}
Blend2D.__index = Blend2D

-- definition: { x = 'dirX', y = 'dirY', points = { { 0, 1, node }, { 1, 0, node } }, sync = true }
function Blend2D.new(definition, build)
    assert(type(definition.points) == 'table' and #definition.points >= 1, 'Blend2D needs points')
    local points = {}
    for i, point in ipairs(definition.points) do
        points[i] = { x = point[1], y = point[2], node = build(point[3]) }
    end
    local children = {}
    for i, point in ipairs(points) do
        children[i] = point.node
    end
    return setmetatable({
        kind = 'Blend2D',
        definition = definition,
        x = definition.x,
        y = definition.y,
        sync = definition.sync ~= false,
        points = points,
        weights = {},
        children = children,
    }, Blend2D)
end

function Blend2D:collect(list)
    for _, point in ipairs(self.points) do
        point.node:collect(list)
    end
end

-- Normalised weights of every point for the sample (px, py).
function Blend2D:solve(px, py)
    local points, weights = self.points, self.weights
    local total = 0
    for i, a in ipairs(points) do
        local w = 1
        for j, b in ipairs(points) do
            if i ~= j then
                local vx, vy = b.x - a.x, b.y - a.y
                local square = vx * vx + vy * vy
                if square > 1e-12 then
                    local f = ((px - a.x) * vx + (py - a.y) * vy) / square
                    w = math.min(w, math.max(0, 1 - f))
                end
            end
        end
        weights[i] = w
        total = total + w
    end
    if total <= 1e-9 then
        local nearest, best = 1, math.huge
        for i, a in ipairs(points) do
            local d = (px - a.x) ^ 2 + (py - a.y) ^ 2
            if d < best then
                nearest, best = i, d
            end
        end
        for i = 1, #points do
            weights[i] = i == nearest and 1 or 0
        end
        return weights
    end
    for i = 1, #points do
        weights[i] = weights[i] / total
    end
    return weights
end

function Blend2D:evaluate(weight, scale, context)
    local tree = context.tree
    local weights = self:solve(Params.read(tree, self.x), Params.read(tree, self.y))
    context:group(self)
    for i, point in ipairs(self.points) do
        if weights[i] > 0 then
            point.node:evaluate(weight * weights[i], scale, context)
        end
    end
end

function Blend2D:restart()
    for _, point in ipairs(self.points) do
        point.node:restart()
    end
end

function Blend2D:finished()
    return self.points[1].node:finished()
end

return Blend2D
