-- Transition: plays one of several inputs, chosen by a parameter, and crossfades when the choice
-- changes. A light switch for a few poses where a whole StateMachine would be too much.
--
--   { type = 'Transition', param = 'stance', fade = 0.25, curve = 'smooth',
--     inputs = { { 'Stand', standNode }, { 'Crouch', crouchNode }, { 'Prone', proneNode } } }
--   tree:set('stance', 'Crouch')      -- an input name, or its 1-based index
--
-- `inputs` may also be a map `{ Stand = node, ... }` (ordered by name). `curve`: 'linear',
-- 'smooth' (smoothstep), 'easeIn', 'easeOut' or a function of 0..1. `reset = false` keeps a
-- chosen input where it was instead of restarting it. A change during a fade starts from the
-- weights reached so far.
local Curves = require('../curves')

local Transition = {}
Transition.__index = Transition

function Transition.new(definition, build)
    assert(type(definition.inputs) == 'table' and next(definition.inputs), 'Transition needs inputs')
    local names, nodes = {}, {}
    if definition.inputs[1] ~= nil and type(definition.inputs[1]) == 'table' and not definition.inputs[1].kind then
        for i, entry in ipairs(definition.inputs) do
            names[i], nodes[i] = tostring(entry[1]), build(entry[2])
        end
    else
        local keys = {}
        for name in pairs(definition.inputs) do
            keys[#keys + 1] = name
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        for i, name in ipairs(keys) do
            names[i], nodes[i] = tostring(name), build(definition.inputs[name])
        end
    end
    local curve = Curves.get(definition.curve)
    local levels = {}
    for i = 1, #nodes do
        levels[i] = 0
    end
    return setmetatable({
        kind = 'Transition',
        definition = definition,
        param = definition.param,
        fade = definition.fade or 0.2,
        curve = curve,
        reset = definition.reset ~= false,
        sync = definition.sync == true,
        names = names,
        levels = levels,
        children = nodes,
    }, Transition)
end

function Transition:collect(list)
    for _, child in ipairs(self.children) do
        child:collect(list)
    end
end

-- Index of the chosen input.
function Transition:choice(tree)
    local value = self.param ~= nil and tree.params[self.param] or nil
    if type(value) == 'number' then
        return math.max(1, math.min(#self.children, math.floor(value)))
    end
    for i, name in ipairs(self.names) do
        if name == value then
            return i
        end
    end
    return self.current or 1
end

function Transition:evaluate(weight, scale, context)
    local choice = self:choice(context.tree)
    if choice ~= self.current then
        if not self.current then
            self.levels[choice] = 1
        elseif self.reset then
            self.children[choice]:restart()
        end
        self.current = choice
    end
    local levels, sum = self.levels, 0
    local step = self.fade > 0 and context.dt / self.fade or 1
    for i = 1, #levels do
        local target = i == choice and 1 or 0
        if levels[i] < target then
            levels[i] = math.min(target, levels[i] + step)
        elseif levels[i] > target then
            levels[i] = math.max(target, levels[i] - step)
        end
        sum = sum + self.curve(levels[i])
    end
    context:group(self)
    for i, child in ipairs(self.children) do
        local w = self.curve(levels[i])
        if w > 0 and sum > 0 then
            child:evaluate(weight * w / sum, scale, context)
        end
    end
end

function Transition:restart()
    for i, child in ipairs(self.children) do
        child:restart()
        self.levels[i] = i == self.current and 1 or 0
    end
end

function Transition:finished()
    return self.current ~= nil and self.children[self.current]:finished()
end

return Transition
