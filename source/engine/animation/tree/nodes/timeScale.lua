-- TimeScale: plays its child faster or slower (`scale` is a number, a parameter or a function).
local Params = require('../params')

local TimeScale = {}
TimeScale.__index = TimeScale

function TimeScale.new(definition, build)
    local child = build(definition.child)
    return setmetatable({
        kind = 'TimeScale',
        definition = definition,
        scale = definition.scale or 1,
        child = child,
        children = { child },
    }, TimeScale)
end

function TimeScale:collect(list)
    self.child:collect(list)
end

function TimeScale:evaluate(weight, scale, context)
    self.child:evaluate(weight, scale * Params.read(context.tree, self.scale, 1), context)
end

function TimeScale:restart()
    self.child:restart()
end

function TimeScale:finished()
    return self.child:finished()
end

return TimeScale
