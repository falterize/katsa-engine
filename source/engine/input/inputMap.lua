-- InputMap: named actions bound to keys, mouse buttons, the wheel, gamepad buttons and gamepad axes.
-- Game code asks for an action by name and never for a device:
--
--   map:addAction('jump', { 'key:space', 'pad:a' })
--   map:addAction('left', { 'key:a', 'axis:leftx-' })
--   if map:justPressed('jump') then ... end        -- true for the one update after the press
--   local x = map:getAxis('left', 'right')         -- -1..1
--
-- An event is one string: `key:<name>`, `mouse:<button>`, `wheel:up|down`, `pad:<button>`,
-- `axis:<axis>+|-` (the pad axis moving in that direction; the triggers are axes too, as in
-- SDL and Godot). A bare name means a key. Strings are
-- the only representation, so a map saves and loads as plain data (`toData` / `loadData`).
--
-- Devices feed the map through `setEventStrength(event, strength)`; the owner (Input) calls `update()` once
-- per frame before gameplay reads it, which publishes the edges `justPressed` / `justReleased` and
-- runs the listeners registered with `onPressed` / `onReleased`.
local Vector2 = require('../math.vector2')

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
        self:loadData(definitions)
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

-- Defines an action. `deadzone` (0..1, default 0.2) is how far an axis event must travel before
-- the action counts as down. Defining a name twice is an error: use `setEvents` to rebind.
function InputMap:addAction(name, events, deadzone)
    assert(type(name) == 'string' and name ~= '', 'Input action name must be a non-empty string')
    assert(not self.actions[name], 'Input action "' .. name .. '" already exists')
    local action = { name = name, events = {}, values = {}, raw = 0, down = false, deadzone = 0 }
    self.actions[name], self.order[#self.order + 1] = action, name
    self:setDeadzone(name, deadzone or DEFAULT_DEADZONE)
    return self:setEvents(name, events)
end

-- Replaces every event of an action (the rebinding call).
function InputMap:setEvents(name, events)
    local action = get(self, name)
    action.events, action.values = {}, {}
    for _, event in ipairs(eventList(events)) do
        action.events[#action.events + 1] = InputMap.normalize(event)
    end
    self.index = nil
    self:refresh(action)
    return self
end

function InputMap:setDeadzone(name, deadzone)
    assert(type(deadzone) == 'number' and deadzone >= 0 and deadzone < 1, 'deadzone must be in 0..1')
    get(self, name).deadzone = deadzone
    return self
end

function InputMap:getDeadzone(name)
    return get(self, name).deadzone
end

function InputMap:hasAction(name)
    return self.actions[name] ~= nil
end

function InputMap:getActions()
    local list = {}
    for i, name in ipairs(self.order) do
        list[i] = name
    end
    return list
end

-- A copy of the action's event strings.
function InputMap:getEvents(name)
    local list = {}
    for i, event in ipairs(get(self, name).events) do
        list[i] = event
    end
    return list
end

-- Adds one event; binding the same event twice is harmless.
function InputMap:addEvent(name, event)
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

function InputMap:removeEvent(name, event)
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
function InputMap:clearEvents(name)
    return self:setEvents(name, {})
end

function InputMap:removeAction(name)
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
function InputMap:setEventStrength(event, strength)
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
-- Pressed from code stays down until `releaseAction`, independent of real devices.
function InputMap:pressAction(name, strength)
    local action = get(self, name)
    action.virtual = strength or 1
    self:refresh(action)
    return self
end

function InputMap:releaseAction(name)
    local action = get(self, name)
    action.virtual = nil
    self:refresh(action)
    return self
end

-- Press and release in one go: the action reports `pressed` and `released` on the next update.
function InputMap:triggerAction(name)
    return self:pressAction(name):releaseAction(name)
end

-- A momentary event (a wheel notch): pressed and released at once.
function InputMap:tapEvent(event)
    self:setEventStrength(event, 1)
    self:setEventStrength(event, 0)
end

-- A gamepad axis value -1..1 becomes the `+` and `-` events.
function InputMap:setAxisValue(axis, value)
    self:setEventStrength('axis:' .. axis .. '+', value > 0 and value or 0)
    self:setEventStrength('axis:' .. axis .. '-', value < 0 and -value or 0)
end

-- Calls `callback(event)` once with the next pressed event, for "press a key to rebind". The event
-- is consumed: no action sees it. Returns false while another listen is waiting.
function InputMap:listenForEvent(callback)
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

local function connect(self, name, callback, phase)
    get(self, name)
    assert(type(callback) == 'function', 'listener needs a callback')
    local list = self.listeners[name] or {}
    self.listeners[name] = list
    local connection = { callback = callback, phase = phase }
    list[#list + 1] = connection
    -- Same shape as node signals: the result has :disconnect().
    function connection:disconnect()
        for i, known in ipairs(list) do
            if known == self then
                table.remove(list, i)
                return
            end
        end
    end
    return connection
end

-- Runs `callback(name)` when the action is pressed. Returns a connection with :disconnect().
function InputMap:onPressed(name, callback)
    return connect(self, name, callback, 'pressed')
end

function InputMap:onReleased(name, callback)
    return connect(self, name, callback, 'released')
end

function InputMap:isDown(name)
    return get(self, name).down
end

-- True for the update that follows the press (`justReleased` likewise), even when the key was
-- released again before that update.
function InputMap:justPressed(name)
    get(self, name)
    return self.pressedNow[name] == true
end

function InputMap:justReleased(name)
    get(self, name)
    return self.releasedNow[name] == true
end

-- 0 while up; keys give 1, an axis gives its travel past the deadzone rescaled to 0..1.
function InputMap:getStrength(name)
    local action = get(self, name)
    if not action.down then
        return 0
    end
    return (action.raw - action.deadzone) / (1 - action.deadzone)
end

-- Strength before the deadzone, 0..1: what a stick reports. `getVector` works on it.
function InputMap:getRawStrength(name)
    return get(self, name).raw
end

-- `positive` minus `negative`, -1..1: map:getAxis('left', 'right').
function InputMap:getAxis(negative, positive)
    return self:getStrength(positive) - self:getStrength(negative)
end

-- A vector from four actions (x = right - left, y = down - up), as Godot's Input.get_vector:
-- the deadzone cuts the vector as a whole (round, not square), the length is at most 1, so a stick
-- pushed a little left and up gives a short vector pointing there. Fills `out` (an array {x, y})
-- or returns a new Vector2.
function InputMap:getVector(left, right, up, down, out)
    local x = self:getRawStrength(right) - self:getRawStrength(left)
    local y = self:getRawStrength(down) - self:getRawStrength(up)
    local zone = (
        self:getDeadzone(left)
        + self:getDeadzone(right)
        + self:getDeadzone(up)
        + self:getDeadzone(down)
    ) / 4
    local length = math.sqrt(x * x + y * y)
    if length <= zone or length == 0 then
        x, y = 0, 0
    else
        local scale = math.min(1, (length - zone) / (1 - zone)) / length
        x, y = x * scale, y * scale
    end
    if out then
        out[1], out[2] = x, y
        return out
    end
    return Vector2.new(x, y)
end

-- Sets four actions from a vector (an array or Vector2), the way a stick would: `{ -0.3, -0.5 }`
-- presses `left` at 0.3 and `up` at 0.5. For on-screen sticks; `releaseVector` lets go.
function InputMap:pressVector(left, right, up, down, vector)
    local x, y = vector[1], vector[2]
    self:pressAction(left, x < 0 and -x or 0)
    self:pressAction(right, x > 0 and x or 0)
    self:pressAction(up, y < 0 and -y or 0)
    self:pressAction(down, y > 0 and y or 0)
    return self
end

function InputMap:releaseVector(left, right, up, down)
    for _, name in ipairs({ left, right, up, down }) do
        self:releaseAction(name)
    end
    return self
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

-- Defines or rebinds every action of `data` (the format of toData). Actions of the map that
-- `data` does not mention stay as they are, so a save from an older version keeps new actions at
-- their defaults.
function InputMap:loadData(data)
    local names = {}
    for name in pairs(data) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local entry = data[name]
        local events, deadzone = entry, nil
        if type(entry) == 'table' and entry.events then
            events, deadzone = entry.events, entry.deadzone
        end
        if self.actions[name] then
            self:setEvents(name, events)
            if deadzone then
                self:setDeadzone(name, deadzone)
            end
        else
            self:addAction(name, events, deadzone)
        end
    end
    return self
end

return InputMap
