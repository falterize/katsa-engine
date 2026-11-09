-- StateMachine: named states (each a graph node) joined by transitions that crossfade.
--
--   { type = 'StateMachine', start = 'Idle', fade = 0.2,
--     states = { Idle = idleNode, Run = runNode, Jump = { clip = 'Player_Jump', loop = false } },
--     transitions = {
--         { from = 'Idle', to = 'Run', when = function(p) return p.speed > 0.1 end },
--         { from = '*', to = 'Jump', when = 'jump', fade = 0.1 },       -- parameter or trigger name
--         { from = 'Jump', to = 'Idle', onFinish = true },              -- when the clip ends
--     } }
--
-- Transitions are tried in order each update; the first whose condition holds and whose `to`
-- differs from the current state fires. A target state restarts from its first frame.
local Params = require('../params')

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(definition, build)
    assert(type(definition.states) == 'table' and next(definition.states), 'A state machine needs states')
    local states, names = {}, {}
    for name, state in pairs(definition.states) do
        states[name] = build(state)
        names[#names + 1] = name
    end
    table.sort(names)
    local start = definition.start or names[1]
    assert(states[start], 'Unknown start state: ' .. tostring(start))
    for _, transition in ipairs(definition.transitions or {}) do
        assert(states[transition.to], 'Unknown transition target: ' .. tostring(transition.to))
        assert(
            transition.from == '*' or states[transition.from],
            'Unknown transition source: ' .. tostring(transition.from)
        )
    end
    local children = {}
    for i, name in ipairs(names) do
        children[i] = states[name]
    end
    return setmetatable({
        kind = 'StateMachine',
        definition = definition,
        name = definition.name,
        states = states,
        names = names,
        transitions = definition.transitions or {},
        fade = definition.fade or 0.2,
        current = start,
        children = children,
    }, StateMachine)
end

function StateMachine:collect(list)
    for _, name in ipairs(self.names) do
        self.states[name]:collect(list)
    end
end

-- Switches to `name`, crossfading over `fade` seconds (the machine default when omitted).
function StateMachine:travel(name, fade, tree)
    assert(self.states[name], 'Unknown state: ' .. tostring(name))
    if name == self.current then
        return
    end
    local from = self.current
    self.previous = self.current
    self.current = name
    self.fadeDuration = fade or self.fade
    self.fadeTime = 0
    self.states[name]:restart()
    if tree and tree.onStateChanged then
        tree.onStateChanged(self, from, name)
    end
end

local function holds(transition, machine, tree)
    local condition = transition.when
    if condition ~= nil then
        local kind = type(condition)
        if kind == 'function' then
            return condition(tree.params, tree) and true or false
        elseif kind == 'string' then
            local value = tree.params[condition]
            return value ~= nil and value ~= false and value ~= 0
        end
        return condition and true or false
    end
    if transition.onFinish then
        return machine.states[machine.current]:finished()
    end
    return false
end

function StateMachine:step(dt, tree)
    if self.previous then
        self.fadeTime = self.fadeTime + dt
        if self.fadeTime >= self.fadeDuration then
            self.previous = nil
        end
    end
    for _, transition in ipairs(self.transitions) do
        if
            (transition.from == '*' or transition.from == self.current)
            and transition.to ~= self.current
            and holds(transition, self, tree)
        then
            self:travel(transition.to, transition.fade, tree)
            break
        end
    end
end

function StateMachine:evaluate(weight, scale, context)
    self:step(context.dt, context.tree)
    local previous = self.previous
    if previous then
        local t = self.fadeDuration > 0 and self.fadeTime / self.fadeDuration or 1
        self.states[previous]:evaluate(weight * (1 - t), scale, context)
        self.states[self.current]:evaluate(weight * t, scale, context)
    else
        self.states[self.current]:evaluate(weight, scale, context)
    end
end

function StateMachine:restart()
    self.states[self.current]:restart()
end

function StateMachine:finished()
    return self.states[self.current]:finished()
end

return StateMachine
