-- InputMap: named actions bound to keys, mouse buttons, the wheel, gamepad buttons and gamepad axes.
-- Game code asks for an action by name and never for a device:
--
--   map:action('jump', { 'key:space', 'pad:a' })
--   map:action('left', { 'key:a', 'axis:leftx-' })
--   if map:pressed('jump') then ... end            -- true for the one update after the press
--   local x = map:axis('left', 'right')            -- -1..1
--
-- An event is one string: `key:<name>`, `mouse:<button>`, `wheel:up|down`, `pad:<button>`,
-- `axis:<axis>+|-` (the pad axis moving in that direction). A bare name means a key. Strings are
-- the only representation, so a map saves and loads as plain data (`toData` / `load`).
--
-- Devices feed the map through `setEvent(event, strength)`; the owner (Input) calls `update()` once
-- per frame before gameplay reads it, which publishes the edges `pressed` / `released` and runs the
-- listeners registered with `on`.
local InputMap = {}
InputMap.__index = InputMap

local DEFAULT_DEADZONE = 0.2 -- same radial zone as katsa.gamepad sticks in Input
local KINDS = { key = true, mouse = true, wheel = true, pad = true, axis = true }
local BUTTONS = {
    a = true, b = true, x = true, y = true, back = true, guide = true, start = true,
    leftstick = true, rightstick = true, leftshoulder = true, rightshoulder = true,
    dpup = true, dpdown = true, dpleft = true, dpright = true, misc1 = true,
    paddle1 = true, paddle2 = true, paddle3 = true, paddle4 = true, touchpad = true,
}
local AXES = {
    leftx = true, lefty = true, rightx = true, righty = true, triggerleft = true, triggerright = true,
}

-- Event constructors, `InputMap.event.key('space')`: the same strings the tables accept, checked
-- while you type them.
InputMap.event = {}

function InputMap.event.key(name)
    return InputMap.normalize('key:' .. name)
end

function InputMap.event.mouse(button)
    return InputMap.normalize('mouse:' .. button)
end

function InputMap.event.wheel(direction)
    return InputMap.normalize('wheel:' .. direction)
end

function InputMap.event.pad(button)
    return InputMap.normalize('pad:' .. button)
end

function InputMap.event.axis(axis, sign)
    return InputMap.normalize('axis:' .. axis .. (sign or '+'))
end

-- Returns the canonical event string or raises an error naming the bad part.
function InputMap.normalize(event)
    assert(type(event) == 'string' and event ~= '', 'Input event must be a non-empty string')
    local kind, value = event:match('^(%a+):(.+)$')
    if not kind then
        kind, value = 'key', event
    end
    kind, value = kind:lower(), value:lower()
    assert(KINDS[kind], 'Unknown input event kind in "' .. event .. '"')
    if kind == 'mouse' then
        assert(tonumber(value), 'mouse event needs a button number: ' .. event)
        value = tostring(tonumber(value))
    elseif kind == 'wheel' then
        assert(value == 'up' or value == 'down', 'wheel event is wheel:up or wheel:down')
    elseif kind == 'pad' then
        assert(BUTTONS[value], 'Unknown gamepad button in "' .. event .. '"')
    elseif kind == 'axis' then
        local axis, sign = value:match('^(%a+)([%+%-])$')
        assert(axis and AXES[axis], 'axis event is axis:<axis>+ or axis:<axis>-: ' .. event)
        value = axis .. sign
    end
    return kind .. ':' .. value
end

function InputMap.new(definitions)
    local self = setmetatable({
        actions = {}, -- name -> { events, deadzone, values, raw, down }
        order = {}, -- names in definition order
        index = nil, -- event -> actions, rebuilt when a binding changes
        axes = {}, -- gamepad axes some action listens to (read by the owner every frame)
        pressedNow = {},
        releasedNow = {},
        pressedNext = {},
        releasedNext = {},
        listeners = {},
    }, InputMap)
    if definitions then
        self:load(definitions)
    end
    return self
end

local function get(self, name)
    return assert(self.actions[name], 'Unknown input action "' .. tostring(name) .. '"')
end

local function eventList(events)
    if type(events) == 'string' then
        return { events }
    end
    return events or {}
end

-- Defines an action, or replaces the events of an existing one. `deadzone` (0..1, default 0.2)
-- is how far an axis event must travel before the action counts as down.
function InputMap:action(name, events, deadzone)
    assert(type(name) == 'string' and name ~= '', 'Input action name must be a non-empty string')
    local action = self.actions[name]
    if not action then
        action = { name = name, events = {}, values = {}, raw = 0, down = false }
        self.actions[name], self.order[#self.order + 1] = action, name
    end
    action.deadzone = deadzone or action.deadzone or DEFAULT_DEADZONE
    assert(action.deadzone >= 0 and action.deadzone < 1, 'deadzone must be in 0..1')
    action.events, action.values = {}, {}
    for _, event in ipairs(eventList(events)) do
        action.events[#action.events + 1] = InputMap.normalize(event)
    end
    self.index = nil
    return self
end

function InputMap:has(name)
    return self.actions[name] ~= nil
end

function InputMap:names()
    local list = {}
    for i, name in ipairs(self.order) do
        list[i] = name
    end
    return list
end

-- A copy of the action's event strings.
function InputMap:events(name)
    local list = {}
    for i, event in ipairs(get(self, name).events) do
        list[i] = event
    end
    return list
end

-- Adds one event; binding the same event twice is harmless.
function InputMap:bind(name, event)
    local action = get(self, name)
    event = InputMap.normalize(event)
    for _, known in ipairs(action.events) do
        if known == event then
            return self
        end
    end
    action.events[#action.events + 1] = event
    self.index = nil
    return self
end

function InputMap:unbind(name, event)
    local action = get(self, name)
    event = InputMap.normalize(event)
    for i, known in ipairs(action.events) do
        if known == event then
            table.remove(action.events, i)
            action.values[event] = nil
            self.index = nil
            self:refresh(action)
            break
        end
    end
    return self
end

-- Removes every event of an action but keeps the action (a rebinding screen starts here).
function InputMap:clear(name)
    return self:action(name, {})
end

function InputMap:remove(name)
    if not self.actions[name] then
        return self
    end
    self.actions[name], self.listeners[name] = nil, nil
    for i, known in ipairs(self.order) do
        if known == name then
            table.remove(self.order, i)
            break
        end
    end
    self.index = nil
    return self
end

-- Rebuilds event -> actions, and the list of gamepad axes the owner has to read.
local function buildIndex(self)
    local index, axes = {}, {}
    for _, action in pairs(self.actions) do
        for _, event in ipairs(action.events) do
            local list = index[event]
            if not list then
                list = {}
                index[event] = list
            end
            list[#list + 1] = action
            local axis = event:match('^axis:(%a+)[%+%-]$')
            if axis then
                axes[axis] = true
            end
        end
    end
    self.index, self.axes = index, axes
    return index
end

-- Recomputes one action's state from its event values and records the edge when it changed.
function InputMap:refresh(action)
    local raw = action.virtual or 0
    for _, event in ipairs(action.events) do
        local value = action.values[event]
        if value and value > raw then
            raw = value
        end
    end
    action.raw = raw
    local down = raw > 0 and raw >= action.deadzone
    if down ~= action.down then
        action.down = down
        if down then
            self.pressedNext[action.name] = true
        else
            self.releasedNext[action.name] = true
        end
    end
end

-- Device input: `strength` 0 releases the event, 1 is a plain press, axes pass their travel.
-- While `listen` waits, the first pressed event goes to the listener and reaches no action.
function InputMap:setEvent(event, strength)
    local capture = self.capture
    if capture then
        if strength >= 0.5 then
            self.capture = nil
            capture(event)
        end
        return
    end
    local actions = (self.index or buildIndex(self))[event]
    if not actions then
        return
    end
    for i = 1, #actions do
        local action = actions[i]
        if action.values[event] ~= strength then
            action.values[event] = strength
            self:refresh(action)
        end
    end
end

-- Code-driven input, for on-screen buttons and tests: the action behaves as if one of its own
-- events was pressed, whatever it is bound to. `strength` is 0..1 (default 1) like an axis.
-- Pressed from code stays down until `release`, independent of real devices.
function InputMap:press(name, strength)
    local action = get(self, name)
    action.virtual = strength or 1
    self:refresh(action)
    return self
end

function InputMap:release(name)
    local action = get(self, name)
    action.virtual = nil
    self:refresh(action)
    return self
end

-- Press and release in one go: the action reports `pressed` and `released` on the next update.
function InputMap:trigger(name)
    return self:press(name):release(name)
end

-- A momentary event (a wheel notch): pressed and released at once.
function InputMap:tap(event)
    self:setEvent(event, 1)
    self:setEvent(event, 0)
end

-- A gamepad axis value -1..1 becomes the `+` and `-` events.
function InputMap:setAxis(axis, value)
    self:setEvent('axis:' .. axis .. '+', value > 0 and value or 0)
    self:setEvent('axis:' .. axis .. '-', value < 0 and -value or 0)
end

-- Calls `callback(event)` once with the next pressed event, for "press a key to rebind". The event
-- is consumed: no action sees it. Returns false while another listen is waiting.
function InputMap:listen(callback)
    assert(type(callback) == 'function', 'listen needs a callback')
    if self.capture then
        return false
    end
    self.capture = callback
    return true
end

function InputMap:cancelListen()
    self.capture = nil
end

-- Publishes the edges collected since the last call and runs the listeners. Call once per frame,
-- before gameplay reads the map.
function InputMap:update()
    self.pressedNow, self.pressedNext = self.pressedNext, self.pressedNow
    self.releasedNow, self.releasedNext = self.releasedNext, self.releasedNow
    for name in pairs(self.pressedNext) do
        self.pressedNext[name] = nil
    end
    for name in pairs(self.releasedNext) do
        self.releasedNext[name] = nil
    end
    for name in pairs(self.pressedNow) do
        local list = self.listeners[name]
        for i = 1, list and #list or 0 do
            if list[i].phase == 'pressed' then
                list[i].callback(name)
            end
        end
    end
    for name in pairs(self.releasedNow) do
        local list = self.listeners[name]
        for i = 1, list and #list or 0 do
            if list[i].phase == 'released' then
                list[i].callback(name)
            end
        end
    end
end

-- Runs `callback(name)` when the action is pressed (or `phase = 'released'`). Returns a function
-- that removes the listener.
function InputMap:on(name, callback, phase)
    get(self, name)
    assert(type(callback) == 'function', 'on needs a callback')
    phase = phase or 'pressed'
    assert(phase == 'pressed' or phase == 'released', 'phase is "pressed" or "released"')
    local list = self.listeners[name] or {}
    self.listeners[name] = list
    local entry = { callback = callback, phase = phase }
    list[#list + 1] = entry
    return function()
        for i, known in ipairs(list) do
            if known == entry then
                table.remove(list, i)
                return
            end
        end
    end
end

function InputMap:isDown(name)
    return get(self, name).down
end

-- True for the update that follows the press (released likewise), even when the key was
-- released again before that update.
function InputMap:pressed(name)
    get(self, name)
    return self.pressedNow[name] == true
end

function InputMap:released(name)
    get(self, name)
    return self.releasedNow[name] == true
end

-- 0 while up; keys give 1, an axis gives its travel past the deadzone rescaled to 0..1.
function InputMap:strength(name)
    local action = get(self, name)
    if not action.down then
        return 0
    end
    return (action.raw - action.deadzone) / (1 - action.deadzone)
end

-- `positive` minus `negative`, -1..1: map:axis('left', 'right').
function InputMap:axis(negative, positive)
    return self:strength(positive) - self:strength(negative)
end

-- A vector from four actions, shorter than 1 on diagonals: x = right - left, y = down - up.
function InputMap:vector(left, right, up, down)
    local x, y = self:axis(left, right), self:axis(up, down)
    local length = math.sqrt(x * x + y * y)
    if length > 1 then
        x, y = x / length, y / length
    end
    return x, y
end

-- Releases everything (focus loss, scene change) without publishing release edges.
function InputMap:reset()
    for _, action in pairs(self.actions) do
        action.values, action.raw, action.down, action.virtual = {}, 0, false, nil
    end
    for name in pairs(self.pressedNext) do
        self.pressedNext[name] = nil
    end
    for name in pairs(self.releasedNext) do
        self.releasedNext[name] = nil
    end
    self.capture = nil
end

-- Plain data for save files: { jump = { 'key:space', 'pad:a' }, aim = { events = {...}, deadzone = 0.4 } }.
function InputMap:toData()
    local data = {}
    for _, name in ipairs(self.order) do
        local action = self.actions[name]
        local events = {}
        for i, event in ipairs(action.events) do
            events[i] = event
        end
        if action.deadzone == DEFAULT_DEADZONE then
            data[name] = events
        else
            data[name] = { events = events, deadzone = action.deadzone }
        end
    end
    return data
end

-- Defines every action of `data` (the format of toData). Actions of the map that `data` does not
-- mention stay as they are, so a save from an older version keeps new actions at their defaults.
function InputMap:load(data)
    local names = {}
    for name in pairs(data) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local entry = data[name]
        if entry.events then
            self:action(name, entry.events, entry.deadzone)
        else
            self:action(name, entry)
        end
    end
    return self
end

return InputMap
