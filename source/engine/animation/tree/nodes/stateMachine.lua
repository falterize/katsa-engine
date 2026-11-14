-- StateMachine: named states (each a graph node) joined by transitions that crossfade.
--
--   { type = 'StateMachine', start = 'Idle', fade = 0.2, curve = 'smooth',
--     states = { Idle = idleNode, Run = runNode, Jump = { clip = 'Player_Jump', loop = false } },
--     transitions = {
--         { from = 'Idle', to = 'Run', when = function(p) return p.speed > 0.1 end },
--         { from = '*', to = 'Jump', when = 'jump', fade = 0.1, priority = -1 },
--         { from = 'Jump', to = 'Idle', onFinish = true },                -- when the clip ends
--         { from = 'Run', to = 'Idle', switch = 'AtEnd', advance = 'Disabled' }, -- travel only
--     } }
--
-- Transitions are tried in order of `priority` (lower first, then as listed) each update; the first
-- whose condition holds and whose `to` differs from the current state fires. Per transition:
--   fade, curve   crossfade seconds and shape (machine defaults: `fade`, `curve`)
--   switch        'Immediate' (default), 'Sync' (the new state continues at the old state's phase)
--                 or 'AtEnd' (waits until the current clip is about to end, so the fade finishes
--                 with it)
--   advance       'Auto' (default: fires when `when` holds) or 'Disabled' (only `travel` uses it)
--   reset         false keeps the target where it was instead of restarting it
-- A state named 'End' needs no node: going there ends the machine (`finished()` is true, so a
-- parent machine's `onFinish` transition fires). A state may itself be a StateMachine.
-- `travel(state)` walks the shortest chain of transitions to `state`, honouring each one's
-- `switch`; with no chain it jumps there directly.
local Params = require('../params')
local Curves = require('../curves')
local Phase = require('../phase')

local StateMachine = {}
StateMachine.__index = StateMachine

local END = 'End'

local function normalize(transition, index)
    local copy = {}
    for key, value in pairs(transition) do
        copy[key] = value
    end
    copy.order = index
    copy.priority = copy.priority or 0
    local switch = copy.switch or 'Immediate'
    assert(
        switch == 'Immediate' or switch == 'Sync' or switch == 'AtEnd',
        'Transition switch must be Immediate, Sync or AtEnd'
    )
    copy.switch = switch
    local advance = copy.advance or 'Auto'
    assert(advance == 'Auto' or advance == 'Disabled', 'Transition advance must be Auto or Disabled')
    copy.advance = advance
    copy.curveFunction = copy.curve ~= nil and Curves.get(copy.curve) or nil
    return copy
end

function StateMachine.new(definition, build)
    assert(type(definition.states) == 'table' and next(definition.states), 'A state machine needs states')
    local states, names = {}, {}
    for name, state in pairs(definition.states) do
        assert(name ~= END, "'End' is a reserved state name")
        states[name] = build(state)
        names[#names + 1] = name
    end
    table.sort(names)
    local start = definition.start or names[1]
    assert(states[start], 'Unknown start state: ' .. tostring(start))
    local transitions = {}
    for index, transition in ipairs(definition.transitions or {}) do
        assert(
            states[transition.to] or transition.to == END,
            'Unknown transition target: ' .. tostring(transition.to)
        )
        assert(
            transition.from == '*' or states[transition.from],
            'Unknown transition source: ' .. tostring(transition.from)
        )
        transitions[index] = normalize(transition, index)
    end
    table.sort(transitions, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.order < b.order
    end)
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
        transitions = transitions,
        fade = definition.fade or 0.2,
        curve = Curves.get(definition.curve),
        current = start,
        children = children,
    }, StateMachine)
end

function StateMachine:collect(list)
    for _, name in ipairs(self.names) do
        self.states[name]:collect(list)
    end
end

function StateMachine:node(name)
    return self.states[name]
end

-- Switches to `name`. `fade` seconds (the machine's default when omitted); `options`: { curve,
-- phase = number to start at, reset = false }.
function StateMachine:enter(name, fade, tree, options)
    options = options or {}
    local from = self.current
    self.previous = from
    self.current = name
    self.fadeDuration = fade or self.fade
    self.fadeTime = 0
    self.fadeCurve = options.curve or self.curve
    local node = self.states[name]
    if node then
        if options.phase then
            node:restart()
            Phase.set(node, options.phase)
        elseif options.reset ~= false then
            node:restart()
        end
    end
    if tree and tree.onStateChanged then
        tree.onStateChanged(self, from, name)
    end
end

-- Shortest chain of states from the current one to `target` (not including the current one).
function StateMachine:route(target)
    local previous, queue, head = { [self.current] = false }, { self.current }, 1
    while queue[head] do
        local state = queue[head]
        head = head + 1
        if state == target then
            break
        end
        for _, transition in ipairs(self.transitions) do
            if
                (transition.from == '*' or transition.from == state)
                and previous[transition.to] == nil
            then
                previous[transition.to] = state
                queue[#queue + 1] = transition.to
            end
        end
    end
    if previous[target] == nil then
        return nil
    end
    local path = {}
    local state = target
    while state ~= self.current do
        table.insert(path, 1, state)
        state = previous[state]
    end
    return path
end

function StateMachine:travel(name, fade, tree)
    assert(self.states[name] or name == END, 'Unknown state: ' .. tostring(name))
    if name == self.current then
        self.path = nil
        return
    end
    local path = self:route(name)
    if path and #path > 1 or path and self:link(self.current, name).switch ~= 'Immediate' then
        self.path, self.pathFade = path, fade
        return
    end
    self.path = nil
    self:enter(name, fade, tree)
end

-- The transition used to go from `from` to `to` (a direct one wins over a wildcard).
function StateMachine:link(from, to)
    local wildcard
    for _, transition in ipairs(self.transitions) do
        if transition.to == to then
            if transition.from == from then
                return transition
            elseif transition.from == '*' then
                wildcard = wildcard or transition
            end
        end
    end
    return wildcard
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
        local node = machine.states[machine.current]
        return node == nil or node:finished()
    end
    return false
end

-- Whether `transition` may switch now: 'AtEnd' waits until the current clip is about to finish.
local function ready(machine, transition, dt)
    if transition.switch ~= 'AtEnd' then
        return true
    end
    local node = machine.states[machine.current]
    if not node then
        return true
    end
    local fade = transition.fade or machine.fade
    return Phase.remaining(node) <= fade + dt
end

function StateMachine:fire(transition, tree)
    local options = { curve = transition.curveFunction, reset = transition.reset }
    if transition.switch == 'Sync' then
        local node = self.states[self.current]
        options.phase = node and Phase.get(node) or nil
    end
    self:enter(transition.to, transition.fade or self.pathFade, tree, options)
end

function StateMachine:step(dt, tree)
    if self.previous then
        self.fadeTime = self.fadeTime + dt
        if self.fadeTime >= self.fadeDuration then
            self.previous = nil
        end
    end
    if self.path then
        local nextState = self.path[1]
        local transition = self:link(self.current, nextState)
        if not transition or ready(self, transition, dt) then
            table.remove(self.path, 1)
            if #self.path == 0 then
                self.path = nil
            end
            if transition then
                self:fire(transition, tree)
            else
                self:enter(nextState, self.pathFade, tree)
            end
            self.pathFade = self.path and self.pathFade or nil
        end
        return
    end
    for _, transition in ipairs(self.transitions) do
        if
            transition.advance == 'Auto'
            and (transition.from == '*' or transition.from == self.current)
            and transition.to ~= self.current
            and holds(transition, self, tree)
            and ready(self, transition, dt)
        then
            self:fire(transition, tree)
            break
        end
    end
end

function StateMachine:evaluate(weight, scale, context)
    self:step(context.dt, context.tree)
    local previous = self.previous
    local current = self.states[self.current]
    if previous then
        local t = self.fadeDuration > 0 and self.fadeTime / self.fadeDuration or 1
        t = self.fadeCurve(math.max(0, math.min(1, t)))
        if self.states[previous] then
            self.states[previous]:evaluate(weight * (1 - t), scale, context)
        end
        if current then
            current:evaluate(weight * t, scale, context)
        end
    elseif current then
        current:evaluate(weight, scale, context)
    end
end

function StateMachine:restart()
    local node = self.states[self.current]
    if node then
        node:restart()
    end
end

function StateMachine:finished()
    local node = self.states[self.current]
    return node == nil or node:finished()
end

return StateMachine
