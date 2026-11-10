-- InputMap: named actions bound to keys, mouse buttons, the wheel, gamepad buttons and gamepad axes.
-- Game code asks for an action by name and never for a device:
--
--   map:addAction('jump', { 'key:space', 'pad:a' })
--   map:addAction('left', { 'key:a', 'axis:leftx.left' })
--   map:addAction('save', { 'key:ctrl+key:s' })
--   if map:justPressed('jump') then ... end        -- true for the one update after the press
--   local x = map:getAxis('left', 'right')         -- -1..1
--
-- An action has a list of bindings; any one of them triggers it. A binding is one event or a chord
-- of events joined by `+` that must all be held. An event is one string:
--   key:<name>   mouse:<button>   wheel:up|down   pad:<button>
--   axis:<axis>.<direction>       leftx/rightx .left|.right, lefty/righty .up|.down
--   axis:triggerleft              the triggers are axes with one direction (as in SDL and Godot)
-- Gamepad events take `@<n>` to name the n-th pad (`pad:a@2`); without it any pad counts. A bare
-- name means a key, but a chord needs the prefix of every part (`key:ctrl+key:s`). A binding can be
-- a table `{ 'axis:leftx.left', deadzone = 0.4 }` to override the action's deadzone for it.
-- Strings are the only representation, so a map saves and loads as plain data (`toData` /
-- `loadData`).
--
-- Devices feed the map through `setEventStrength(event, strength, pad)`; the owner (the scene
-- manager) calls `update()` once per frame before gameplay reads it, which publishes the edges
-- `justPressed` / `justReleased` and runs the listeners registered with `onPressed` / `onReleased`.
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
-- axis -> { negative direction, positive direction }; false = a trigger (0..1, one direction)
local AXES = {
    leftx = { 'left', 'right' },
    lefty = { 'up', 'down' },
    rightx = { 'left', 'right' },
    righty = { 'up', 'down' },
    triggerleft = false,
    triggerright = false,
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

function InputMap.event.pad(button, pad)
    return InputMap.normalize('pad:' .. button .. (pad and '@' .. pad or ''))
end

-- `axis('leftx', 'left')`, `axis('triggerright')`.
function InputMap.event.axis(axis, direction, pad)
    return InputMap.normalize(
        'axis:' .. axis .. (direction and '.' .. direction or '') .. (pad and '@' .. pad or '')
    )
end

-- Splits a chord at the `+` that starts another prefixed event (`key:ctrl+key:s`); a `+` inside
-- a key name (`key:kp+`) stays.
local function splitChord(text)
    local parts, start = {}, 1
    for position = 1, #text do
        if text:sub(position, position) == '+' then
            local kind = text:match('^(%a+):', position + 1)
            if kind and KINDS[kind:lower()] then
                parts[#parts + 1] = text:sub(start, position - 1)
                start = position + 1
            end
        end
    end
    parts[#parts + 1] = text:sub(start)
    return parts
end

-- One event: returns its canonical atom (`axis:leftx.left`) and the pad number or nil.
local function parseAtom(text)
    assert(type(text) == 'string' and text ~= '', 'Input event must be a non-empty string')
    local body, pad = text, nil
    local base, number = text:match('^(.-)@(%d+)$')
    if base then
        body, pad = base, tonumber(number)
        assert(pad >= 1, 'Gamepad numbers start at 1: ' .. text)
    end
    local kind, value = body:match('^(%a+):(.+)$')
    if not kind then
        kind, value = 'key', body
    end
    kind, value = kind:lower(), value:lower()
    assert(KINDS[kind], 'Unknown input event kind in "' .. text .. '"')
    assert(
        pad == nil or kind == 'pad' or kind == 'axis',
        'Only gamepad events take @<number>: ' .. text
    )
    if kind == 'key' then
        assert(
            #value == 1 or not value:find('+', 1, true) or value:match('^kp%+$'),
            'A chord needs a prefix on every part (key:ctrl+key:s): ' .. text
        )
    elseif kind == 'mouse' then
        assert(tonumber(value), 'mouse event needs a button number: ' .. text)
        value = tostring(tonumber(value))
    elseif kind == 'wheel' then
        assert(value == 'up' or value == 'down', 'wheel event is wheel:up or wheel:down')
    elseif kind == 'pad' then
        assert(BUTTONS[value], 'Unknown gamepad button in "' .. text .. '"')
    else
        local signed = value:match('^(%a+)[%+%-]$')
        if signed then
            error(
                'Axis directions are words now: axis:' .. signed .. '.left / .right / .up / .down (got "'
                    .. text .. '")'
            )
        end
        local axis, direction = value:match('^(%a+)%.?(%a*)$')
        local directions = axis and AXES[axis]
        assert(
            AXES[axis] ~= nil,
            'Unknown gamepad axis in "' .. text .. '" (leftx, lefty, rightx, righty, triggerleft, triggerright)'
        )
        if directions then
            assert(
                direction == directions[1] or direction == directions[2],
                'Write the direction of ' .. axis .. ': axis:' .. axis .. '.' .. directions[1]
                    .. ' or .' .. directions[2] .. ' (got "' .. text .. '")'
            )
            value = axis .. '.' .. direction
        else
            assert(direction == '', 'A trigger has no direction: axis:' .. axis)
            value = axis
        end
    end
    return kind .. ':' .. value, pad
end

local function atomText(atom, pad)
    return pad and atom .. '@' .. pad or atom
end

-- A binding: one event or a chord, optionally with its own deadzone. The text is canonical
-- (`key:ctrl+key:s`), so the same binding always compares equal.
local function parseBinding(entry)
    local text, deadzone = entry, nil
    if type(entry) == 'table' then
        text, deadzone = entry[1], entry.deadzone
    end
    assert(type(text) == 'string' and text ~= '', 'Input binding must be a non-empty string')
    assert(
        deadzone == nil or type(deadzone) == 'number' and deadzone >= 0 and deadzone < 1,
        'deadzone must be in 0..1'
    )
    local binding, names = { parts = {}, deadzone = deadzone }, {}
    for i, piece in ipairs(splitChord(text)) do
        local atom, pad = parseAtom(piece)
        binding.parts[i] = { atom = atom, pad = pad }
        names[i] = atomText(atom, pad)
    end
    binding.text = table.concat(names, '+')
    return binding
end

-- Returns the canonical text of a binding string or raises an error naming the bad part.
function InputMap.normalize(event)
    return parseBinding(event).text
end

function InputMap.new(definitions)
    local self = setmetatable({
        actions = {}, -- name -> { bindings, deadzone, raw, strength, down, virtual }
        order = {}, -- names in definition order
        atoms = {}, -- event -> { any = strength, [pad] = strength }
        index = nil, -- event -> bindings that use it, rebuilt when a binding changes
        axes = {}, -- gamepad axes some action listens to (read by pollGamepads)
        polledPads = 0,
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

local function entryList(events)
    -- One binding on its own: a string, or a table with a deadzone ({ 'axis:leftx.left', deadzone = 0.4 }).
    if type(events) == 'string' or type(events) == 'table' and events.deadzone ~= nil then
        return { events }
    end
    return events or {}
end

-- Defines an action. `deadzone` (0..1, default 0.2) is how far an axis must travel before the
-- binding counts as down. Defining a name twice is an error: use `setEvents` to rebind.
function InputMap:addAction(name, events, deadzone)
    assert(type(name) == 'string' and name ~= '', 'Input action name must be a non-empty string')
    assert(not self.actions[name], 'Input action "' .. name .. '" already exists')
    local action = {
        name = name,
        bindings = {},
        raw = 0,
        strength = 0,
        down = false,
        deadzone = DEFAULT_DEADZONE,
    }
    self.actions[name], self.order[#self.order + 1] = action, name
    if deadzone then
        self:setDeadzone(name, deadzone)
    end
    return self:setEvents(name, events)
end

-- Adds the actions of `definitions` (the toData format) that do not exist yet and returns their
-- names. Rebinding the player made is kept: a scene's defaults never overwrite an action.
function InputMap:addMissing(definitions)
    local added = {}
    for name, entry in pairs(definitions or {}) do
        if not self.actions[name] then
            local events, deadzone = entry, nil
            if type(entry) == 'table' and entry.events then
                events, deadzone = entry.events, entry.deadzone
            end
            self:addAction(name, events, deadzone)
            added[#added + 1] = name
        end
    end
    return added
end

-- Replaces every binding of an action (the rebinding call).
function InputMap:setEvents(name, events)
    local action = get(self, name)
    action.bindings = {}
    for _, entry in ipairs(entryList(events)) do
        local binding = parseBinding(entry)
        binding.action = action
        action.bindings[#action.bindings + 1] = binding
    end
    self.index = nil
    self:refresh(action)
    return self
end

function InputMap:setDeadzone(name, deadzone)
    assert(
        type(deadzone) == 'number' and deadzone >= 0 and deadzone < 1,
        'deadzone must be in 0..1'
    )
    local action = get(self, name)
    action.deadzone = deadzone
    self:refresh(action)
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

-- The binding texts of an action (a copy): 'key:space', 'key:ctrl+key:s', 'pad:a@2'.
function InputMap:getEvents(name)
    local list = {}
    for i, binding in ipairs(get(self, name).bindings) do
        list[i] = binding.text
    end
    return list
end

-- Adds one binding (a string or `{ text, deadzone = n }`); binding the same one twice is harmless.
function InputMap:addEvent(name, event)
    local action = get(self, name)
    local binding = parseBinding(event)
    for _, known in ipairs(action.bindings) do
        if known.text == binding.text then
            return self
        end
    end
    binding.action = action
    action.bindings[#action.bindings + 1] = binding
    self.index = nil
    self:refresh(action)
    return self
end

function InputMap:removeEvent(name, event)
    local action = get(self, name)
    local text = parseBinding(event).text
    for i, binding in ipairs(action.bindings) do
        if binding.text == text then
            table.remove(action.bindings, i)
            self.index = nil
            self:refresh(action)
            break
        end
    end
    return self
end

-- Removes every binding of an action but keeps the action (a rebinding screen starts here).
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

-- Rebuilds event -> bindings, and the list of gamepad axes the owner has to read.
local function buildIndex(self)
    local index, axes = {}, {}
    for _, action in pairs(self.actions) do
        for _, binding in ipairs(action.bindings) do
            for _, part in ipairs(binding.parts) do
                local list = index[part.atom]
                if not list then
                    list = {}
                    index[part.atom] = list
                end
                list[#list + 1] = binding
                local axis = part.atom:match('^axis:(%a+)')
                if axis then
                    axes[axis] = true
                end
            end
        end
    end
    self.index, self.axes = index, axes
    return index
end

-- Strength of one part right now: the strength of its event on its pad (any pad when none).
local function partValue(self, part)
    local state = self.atoms[part.atom]
    if not state then
        return 0
    end
    return part.pad and state[part.pad] or part.pad == nil and state.any or 0
end

-- Recomputes an action from its bindings (the strongest wins) and records the edge when it
-- changed. A chord is as strong as its weakest part; `raw` ignores the deadzone.
function InputMap:refresh(action)
    local raw, strength = 0, 0
    local function consider(value, deadzone)
        if value > raw then
            raw = value
        end
        if value > 0 and value >= deadzone then
            local scaled = (value - deadzone) / (1 - deadzone)
            if scaled > strength then
                strength = scaled
            end
        end
    end
    for _, binding in ipairs(action.bindings) do
        local value = 1
        for _, part in ipairs(binding.parts) do
            local partStrength = partValue(self, part)
            if partStrength < value then
                value = partStrength
            end
        end
        consider(value, binding.deadzone or action.deadzone)
    end
    if action.virtual then
        consider(action.virtual, action.deadzone)
    end
    action.raw, action.strength = raw, strength
    local down = strength > 0
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
-- `pad` is the gamepad number (1-based) for pad and axis events. While `listenForEvent` waits,
-- the first pressed event goes to the listener and reaches no action.
function InputMap:setEventStrength(event, strength, pad)
    local capture = self.capture
    if capture then
        if strength >= 0.5 then
            self.capture = nil
            capture(event)
        end
        return
    end
    local state = self.atoms[event]
    if not state then
        state = { any = 0 }
        self.atoms[event] = state
    end
    local before = state.any
    if pad then
        state[pad] = strength
        local strongest = 0
        for key, value in pairs(state) do
            if key ~= 'any' and value > strongest then
                strongest = value
            end
        end
        state.any = strongest
    else
        state.any = strength
    end
    local bindings = (self.index or buildIndex(self))[event]
    if not bindings or before == state.any and not pad then
        return
    end
    for i = 1, #bindings do
        self:refresh(bindings[i].action)
    end
end

-- A gamepad axis value -1..1 becomes the events of its two directions (a trigger has one).
function InputMap:setAxisValue(axis, value, pad)
    local directions = AXES[axis]
    assert(directions ~= nil, 'Unknown gamepad axis "' .. tostring(axis) .. '"')
    if directions then
        self:setEventStrength('axis:' .. axis .. '.' .. directions[1], value < 0 and -value or 0, pad)
        self:setEventStrength('axis:' .. axis .. '.' .. directions[2], value > 0 and value or 0, pad)
    else
        self:setEventStrength('axis:' .. axis, value > 0 and value or 0, pad)
    end
end

-- Reads every connected pad for the axes some action listens to. `gamepads` is katsa.gamepad
-- (getCount, byIndex). Pads that disappeared read zero once, so no direction stays stuck.
function InputMap:pollGamepads(gamepads)
    if not self.index then
        buildIndex(self)
    end
    local count = gamepads.getCount()
    local polled = count > self.polledPads and count or self.polledPads
    for number = 1, polled do
        local pad = number <= count and gamepads.byIndex(number) or nil
        for axis in pairs(self.axes) do
            self:setAxisValue(axis, pad and pad:getAxis(axis) or 0, number)
        end
    end
    self.polledPads = count
end

-- A momentary event (a wheel notch): pressed and released at once.
function InputMap:tapEvent(event)
    self:setEventStrength(event, 1)
    self:setEventStrength(event, 0)
end

-- Code-driven input, for on-screen buttons and tests: the action behaves as if one of its own
-- bindings was pressed, whatever it is bound to. `strength` is 0..1 (default 1) like an axis.
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

-- Press and release in one go: the action reports `justPressed` and `justReleased` next update.
function InputMap:triggerAction(name)
    return self:pressAction(name):releaseAction(name)
end

-- Calls `callback(event)` once with the next pressed event, for "press a key to rebind". The event
-- is consumed: no action sees it. Returns false while another listen is waiting.
function InputMap:listenForEvent(callback)
    assert(type(callback) == 'function', 'listenForEvent needs a callback')
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
    return get(self, name).strength
end

-- Strength before the deadzone, 0..1: what a stick reports. `getVector` works on it.
function InputMap:getRawStrength(name)
    return get(self, name).raw
end

-- `positive` minus `negative`, -1..1: map:getAxis('left', 'right').
function InputMap:getAxis(negative, positive)
    return self:getStrength(positive) - self:getStrength(negative)
end

local function vectorOf(self, left, right, up, down, out)
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
    return x, y
end

-- A vector from four actions (x = right - left, y = down - up), as Godot's Input.get_vector:
-- the deadzone cuts the vector as a whole (round, not square), the length is at most 1, so a stick
-- pushed a little left and up gives a short vector pointing there. Fills `out` (an array {x, y})
-- or returns a new Vector2. Y grows downwards like the screen; for a Y-up world use getWorldVector.
function InputMap:getVector(left, right, up, down, out)
    local x, y = vectorOf(self, left, right, up, down)
    if out then
        out[1], out[2] = x, y
        return out
    end
    return Vector2.new(x, y)
end

-- The same vector with Y up (y = up - down), the axes of Node2D and Node3D worlds.
function InputMap:getWorldVector(left, right, up, down, out)
    local x, y = vectorOf(self, left, right, up, down)
    if out then
        out[1], out[2] = x, -y
        return out
    end
    return Vector2.new(x, -y)
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
    self.atoms = {}
    for _, action in pairs(self.actions) do
        action.virtual, action.raw, action.strength, action.down = nil, 0, 0, false
    end
    for name in pairs(self.pressedNext) do
        self.pressedNext[name] = nil
    end
    for name in pairs(self.releasedNext) do
        self.releasedNext[name] = nil
    end
    self.capture = nil
end

-- Plain data for save files: { jump = { 'key:space', 'pad:a' }, aim = { events = {...}, deadzone = 0.4 } };
-- a binding with its own deadzone is `{ 'axis:leftx.left', deadzone = 0.4 }`.
function InputMap:toData()
    local data = {}
    for _, name in ipairs(self.order) do
        local action = self.actions[name]
        local events = {}
        for i, binding in ipairs(action.bindings) do
            events[i] = binding.deadzone and { binding.text, deadzone = binding.deadzone }
                or binding.text
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
