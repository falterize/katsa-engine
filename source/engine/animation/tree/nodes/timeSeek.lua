-- TimeSeek: moves the clips of `child` to a time in seconds when its parameter is set, then clears
-- the parameter (a one-shot request):
--
--   { type = 'TimeSeek', seek = 'jumpTo', child = node }
--   tree:set('jumpTo', 0)             -- rewinds; tree:set('jumpTo', 1.5) seeks to 1.5 s
local TimeSeek = {}
TimeSeek.__index = TimeSeek

function TimeSeek.new(definition, build)
    assert(type(definition.seek) == 'string', 'TimeSeek needs a seek parameter name')
    local child = build(definition.child)
    return setmetatable({
        kind = 'TimeSeek',
        definition = definition,
        seek = definition.seek,
        child = child,
        children = { child },
    }, TimeSeek)
end

function TimeSeek:collect(list)
    self.child:collect(list)
end

function TimeSeek:evaluate(weight, scale, context)
    local params = context.tree.params
    local time = params[self.seek]
    if type(time) == 'number' and time >= 0 then
        params[self.seek] = nil
        local leaves = {}
        self.child:collect(leaves)
        for _, leaf in ipairs(leaves) do
            if leaf.track then
                local duration = leaf:duration()
                leaf.track.timePosition = duration > 0 and (leaf.loop and time % duration or math.min(time, duration)) or 0
            end
        end
    end
    self.child:evaluate(weight, scale, context)
end

function TimeSeek:restart()
    self.child:restart()
end

function TimeSeek:finished()
    return self.child:finished()
end

return TimeSeek
