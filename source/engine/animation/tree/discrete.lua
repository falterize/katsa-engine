-- Blend-space modes Discrete and Carry: one point plays at a time, with no mixing. `Carry` hands the
-- playback phase of the old point to the new one, so a walk keeps its stride when it becomes a run.
local Phase = require('./phase')

local Discrete = {}

-- `list` holds the points ({ node = ... }); `index` is the one that should play.
function Discrete.play(owner, list, index, weight, scale, context)
    local previous = owner.selected
    if previous ~= index then
        local node = list[index].node
        if previous and owner.mode == 'Carry' then
            Phase.set(node, Phase.get(list[previous].node))
        else
            node:restart()
        end
        owner.selected = index
    end
    list[index].node:evaluate(weight, scale, context)
end

Discrete.modes = { 'Interpolated', 'Discrete', 'Carry' }

function Discrete.check(mode)
    assert(
        mode == nil or mode == 'Interpolated' or mode == 'Discrete' or mode == 'Carry',
        'Blend mode must be Interpolated, Discrete or Carry'
    )
    return mode or 'Interpolated'
end

return Discrete
