# InputMap: named actions

`scene.input.map` (an `InputMap`, `source/engine/input/inputMap.lua`) lets gameplay ask for an
action by name instead of a device. Keys, mouse buttons, the wheel, gamepad buttons and gamepad
axes all feed the same actions, and a binding is plain text, so it can be changed at run time
and saved.

```lua
local map = scene.input.map
map:addAction('jump', { 'key:space', 'pad:a' })
map:addAction('left', { 'key:a', 'axis:leftx-' })
map:addAction('right', { 'key:d', 'axis:leftx+' })
map:addAction('fire', { 'mouse:1', 'axis:triggerright+' })

-- in update:
if map:justPressed('jump') then character:jump() end
local x = map:getAxis('left', 'right')          -- -1..1
local move = map:getVector('left', 'right', 'forward', 'back')  -- Vector2, a stick or WASD
```

## Events

One string per event; a bare name is a key.

| Event | Meaning |
| --- | --- |
| `key:space`, `key:a`, `key:lshift` | Keyboard key (names as in `katsa.keyboard`) |
| `mouse:1` | Mouse button number (1 left, 2 right, 3 middle) |
| `wheel:up`, `wheel:down` | One wheel notch (a momentary press) |
| `pad:a`, `pad:leftshoulder` | Gamepad button (names in the gamepad guide) |
| `axis:leftx-`, `axis:leftx+`, `axis:lefty-`, `axis:triggerright+` | A gamepad axis moving in that direction (`leftx-` is the left stick pushed left; `lefty-` is up) |

The triggers are axes (`triggerleft`, `triggerright`, 0..1) because SDL and Godot report them
that way; `leftshoulder`/`rightshoulder` are the buttons.

Typos raise an error as soon as the action is defined. `InputMap.event.key('space')`,
`.mouse(1)`, `.wheel('up')`, `.pad('a')` and `.axis('leftx', '-')` build the same strings.

Scenes can define their actions in `settings.lua`; they exist before the scene script runs:

```lua
return {
    input = {
        jump = { 'key:space', 'pad:a' },
        aim = { events = { 'axis:triggerleft+' }, deadzone = 0.4 },
    },
}
```

## Reading

| Call | Result |
| --- | --- |
| `map:isDown(name)` | Held now |
| `map:justPressed(name)` / `map:justReleased(name)` | True for the one update after the edge, even for a tap shorter than a frame |
| `map:getStrength(name)` | 0..1; keys give 1, an axis gives its travel past the deadzone, rescaled |
| `map:getRawStrength(name)` | 0..1 before the deadzone |
| `map:getAxis(negative, positive)` | `getStrength(positive) - getStrength(negative)` |
| `map:getVector(left, right, up, down, out)` | A Vector2 (or fills `out = {}`): the deadzone cuts the vector as a whole (round, as in Godot), length at most 1 |
| `map:onPressed(name, fn)` / `map:onReleased(name, fn)` | Calls `fn(name)`; returns a connection with `:disconnect()` like node signals |

`deadzone` (default 0.2, per action) is how far an axis must travel to count as down.
Reading an action that was never defined is an error, so a misspelt name does not silently
read as "not pressed". Edges are published at the start of `Input:update`, before the scene
script runs.

## Editing bindings

```lua
map:addEvent('jump', 'key:w')           -- add an event
map:removeEvent('jump', 'pad:a')        -- remove one
map:setEvents('jump', { 'key:j' })      -- replace all events (keeps the deadzone)
map:clearEvents('jump')                 -- keep the action, drop its events
map:setDeadzone('aim', 0.4)
map:removeAction('jump')
map:getEvents('jump')                   -- copy of the event strings
map:hasAction('jump'); map:getActions() -- names in definition order
```

`addAction` on an existing name is an error (use `setEvents`).

### Rebinding screen

`map:listenForEvent(callback)` waits for the next pressed event (key, button, wheel, axis) and hands it
to `callback(event)`; no action sees that event. Use it after the player clicks "change":

```lua
map:clearEvents('jump')
map:listenForEvent(function(event) map:addEvent('jump', event) end)
```

### Saving

```lua
local data = map:toData()   -- { jump = { 'key:space', 'pad:a' }, aim = { events = {...}, deadzone = 0.4 } }
map:loadData(data)              -- defines or rebinds every action in data; others stay as they are
```

Store `data` with the save system (`source/engine/persistence`) and load it right after the
scene starts. The map belongs to one scene's `Input`; to share one set of bindings between
scenes, save and load them. A standalone map works too: `InputMap.new(data)` and feed it with
`map:setEventStrength(event, strength)` and `map:update()`.

## Pressing from code (on-screen buttons, sticks, tests, scripted input)

Every input path can be driven by code, so a touch layout needs nothing special.

| Goal | Call |
| --- | --- |
| Hold a named action | `map:pressAction(name, strength)` ... `map:releaseAction(name)` |
| Press and release at once | `map:triggerAction(name)` (also `input:trigger(name)`) |
| Push a stick by a vector | `map:pressVector('left', 'right', 'up', 'down', { -0.3, -0.5 })`, `map:releaseVector(...)` |
| Fake a device event | `map:setEventStrength('key:space', 1)` then `0`; `map:tapEvent('wheel:up')` |
| Tap a UI node | `input:click(node)` (press and release at its centre) |
| Hold a UI node | `input:press(id, input:nodeCenter(node))` ... `input:release(id, x, y)` |
| Tap a screen point | `input:tap(x, y)`: reaches UI, billboard UI and ClickDetector3D meshes under it |
| Fire a ClickDetector3D | `detector:activate(pointerId)`, or `detector:activate(pointerId, true)` to skip the distance and visibility checks |

`pressVector` splits the vector into the four actions the way a stick does (negative x presses
`left`, positive x `right`, y likewise), so `getVector` and `getAxis` read it back and a screen
joystick drives the same code as a real stick.

```lua
-- A touch button that holds "sprint" while it is pressed.
button:on('press', function() scene.input.map:pressAction('sprint') end)
button:on('release', function() scene.input.map:releaseAction('sprint') end)
```

`input:click(node)` takes the same path as a finger: if another node covers the centre, that
node gets the tap. It covers screen UI; spatial (World2D) nodes need `input:tap` at their
screen position.

## Relation to `input.actions`

The built-in `Move`, `Look`, `Jump` and `Interact` still live in `input.actions`
(see `actions.md`) and drive the default character and camera. `InputMap` is the API for game
actions; both receive the same keyboard, gamepad and mouse events.

Gamepad rumble and sensors are in `katsa.gamepad` (see `gamepad.md`). Not included: key
combinations (`ctrl+s`), per-device filters and a Workspace editor for the map.
