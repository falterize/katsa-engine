# InputMap: named actions

`scene.input.map` (an `InputMap`, `source/engine/input/inputMap.lua`) lets gameplay ask for an
action by name instead of a device. Keys, mouse buttons, the wheel, gamepad buttons and gamepad
axes all feed the same actions, and a binding is plain text, so it can be changed at run time
and saved. The map belongs to the scene manager: every scene sees the same one, so a rebinding
made in a settings scene is still there in the game scene.

```lua
local map = scene.input.map
map:addAction('jump', { 'key:space', 'pad:a' })
map:addAction('left', { 'key:a', 'axis:leftx.left' })
map:addAction('right', { 'key:d', 'axis:leftx.right' })
map:addAction('forward', { 'key:w', 'axis:lefty.up' })
map:addAction('back', { 'key:s', 'axis:lefty.down' })

-- in update:
if map:justPressed('jump') then character:jump() end
local move = map:getVector('left', 'right', 'forward', 'back')  -- Vector2, a stick or WASD
```

## Bindings

An action has a list of bindings; **any one** of them triggers it. A binding is one event or a
chord of events joined by `+` that must **all** be held.

```lua
map:addAction('save', { 'key:ctrl+key:s', 'pad:start+pad:back' })   -- either of two chords
map:addAction('dodge', { 'key:a+axis:leftx.left+key:c' })           -- a key, a stick and a key
```

### Events

| Event | Meaning |
| --- | --- |
| `key:space`, `key:a`, `key:lshift` | Keyboard key (names as in `katsa.keyboard`); a bare `space` also means a key |
| `mouse:1` | Mouse button number (1 left, 2 right, 3 middle) |
| `wheel:up`, `wheel:down` | One wheel notch (a momentary press) |
| `pad:a`, `pad:leftshoulder` | Gamepad button (names in the gamepad guide) |
| `axis:leftx.left`, `axis:leftx.right`, `axis:lefty.up`, `axis:lefty.down` | The left stick pushed that way; `rightx` / `righty` are the right stick |
| `axis:triggerleft`, `axis:triggerright` | The triggers (0..1): they are axes in SDL and Godot; `leftshoulder` / `rightshoulder` are the buttons |
| `pad:a@2`, `axis:leftx.left@2` | The same event on the second gamepad only; without `@n` any pad counts |

`leftx`, `lefty`, `rightx`, `righty` name a stick and a direction: `leftx` is the left stick's
horizontal axis, `lefty` its vertical axis. A stick gives a number, so a stick pushed a little to
the left gives a small strength, not 0 or 1. In a chord every part needs its prefix
(`key:ctrl+key:s`, not `ctrl+s`). Typos raise an error as soon as the action is defined, and the
old signed form `axis:leftx-` is rejected with a hint. `InputMap.event.key('space')`,
`.mouse(1)`, `.wheel('up')`, `.pad('a', 2)` and `.axis('leftx', 'left')` build the same strings
and check them while you write.

### Deadzone

`deadzone` (0..1, default 0.2) is how far an axis must travel before it counts. It belongs to the
action, and a binding can override it with a table; plain strings and tables mix freely:

```lua
map:addAction('aim', { 'key:space', { 'axis:leftx.left', deadzone = 0.4 }, { 'axis:rightx.left', deadzone = 0.15 } })
map:addAction('walk', { 'axis:leftx.left' }, 0.3)    -- third argument: the action's deadzone
map:setDeadzone('walk', 0.25)
```

### Defining actions in `settings.lua`

A scene can bring its own actions; they exist before the scene script runs and leave with the
scene. An action that already exists (a project action, or one the player rebound) is never
overwritten:

```lua
return {
    input = {
        jump = { 'key:space', 'pad:a' },
        aim = { events = { 'axis:triggerleft' }, deadzone = 0.4 },
    },
}
```

## Reading

| Call | Result |
| --- | --- |
| `map:isDown(name)` | Held now |
| `map:justPressed(name)` / `map:justReleased(name)` | True for the one update after the edge, even for a tap shorter than a frame |
| `map:getStrength(name)` | 0..1; keys give 1, an axis gives its travel past the deadzone, rescaled; a chord gives its weakest part |
| `map:getRawStrength(name)` | 0..1 before the deadzone |
| `map:getAxis(negative, positive)` | `getStrength(positive) - getStrength(negative)` |
| `map:getVector(left, right, up, down, out)` | A Vector2 (or fills `out = {}`): the deadzone cuts the vector as a whole (round, as in Godot), length at most 1; Y grows down like the screen |
| `map:getWorldVector(left, right, up, down, out)` | The same with Y up, the axes of Node2D and Node3D worlds |
| `map:onPressed(name, fn)` / `map:onReleased(name, fn)` | Calls `fn(name)`; returns a connection with `:disconnect()` like node signals |

```lua
character.speed = map:isDown('sprint') and 8 or 4
local connection = map:onPressed('jump', function(name) sound:play() end)
connection:disconnect()
```

Reading an action that was never defined is an error, so a misspelt name does not silently read
as "not pressed". Edges are published once per frame before any scene script runs.

## Editing bindings

```lua
map:addEvent('jump', 'key:w')           -- add a binding
map:removeEvent('jump', 'pad:a')        -- remove one
map:setEvents('jump', { 'key:j' })      -- replace all bindings (keeps the deadzone)
map:clearEvents('jump')                 -- keep the action, drop its bindings
map:removeAction('jump')
map:getEvents('jump')                   -- copy of the binding texts
map:hasAction('jump'); map:getActions() -- names in definition order
```

`addAction` on an existing name is an error (use `setEvents`).

### Rebinding screen

`map:listenForEvent(callback)` waits for the next pressed event (key, button, wheel, axis) and
hands it to `callback(event)`; no action sees that event. Use it after the player clicks "change":

```lua
map:clearEvents('jump')
map:listenForEvent(function(event) map:addEvent('jump', event) end)   -- event = 'key:q', 'pad:leftstick' ...
```

### Saving

```lua
local data = map:toData()   -- { jump = { 'key:space', 'pad:a' }, aim = { events = {...}, deadzone = 0.4 } }
map:loadData(data)          -- defines or rebinds every action in data; others stay as they are
```

Store `data` with the save system (`source/engine/persistence`) and load it when the game starts.
A standalone map works too: `InputMap.new(data)`, fed with `map:setEventStrength(event, strength)`
and `map:update()`.

## Pressing from code (on-screen buttons, sticks, tests, scripted input)

Every input path can be driven by code, so a touch layout needs nothing special.

| Goal | Call |
| --- | --- |
| Hold a named action | `map:pressAction(name, strength)` ... `map:releaseAction(name)` |
| Press and release at once | `map:triggerAction(name)` (also `input:trigger(name)`) |
| Push a stick by a vector | `map:pressVector('left', 'right', 'forward', 'back', { -0.3, -0.5 })`, `map:releaseVector(...)` |
| Fake a device event | `map:setEventStrength('key:space', 1)` then `0`; `map:tapEvent('wheel:up')` |
| Click a UI node | `node:click()`; hold with `node:press()` and `node:release()` |
| Tap a screen point | `input:tap(x, y)`: the real path, reaches UI, billboard UI and ClickDetector3D meshes under it and respects what covers them |
| Click a ClickDetector3D | `detector:click()`; hold with `detector:press(id)`, `detector:release(id)`, `detector:cancel(id)` |

`pressVector` splits the vector into the four actions the way a stick does (negative x presses
`left`, positive x `right`, y likewise), so `getVector` and `getAxis` read it back and a screen
joystick drives the same code as a real stick.

```lua
-- A touch button that holds "sprint" while it is pressed.
button:connect('press', function() scene.input.map:pressAction('sprint') end)
button:connect('release', function() scene.input.map:releaseAction('sprint') end)
```

Pointer verbs take the pointer `id` ('mouse', a touch id, or `'code'` by default) so handlers can
tell fingers apart. `UINode:click()` goes straight to that node, whatever covers it;
`input:tap(x, y)` behaves like a finger. UI nodes in screen UI are supported; spatial (World2D)
nodes are reached with `input:tap` at their screen position.

### ClickDetector3D

```lua
local car = world:create('Node3D', { name = 'Car' })          -- many meshes below
local detector = world:create('ClickDetector3D', { radius = 20, priority = 1 }, car)
detector:connect('press', function(id) print('pressed by', id) end)
detector:connect('release', function(id) print('released') end)
detector:connect('click', function(id, target) openDoor() end)
detector:connect('cancel', function(id) print('finger left') end)

detector:click()          -- from code: no distance or visibility check
detector:click('code', true)   -- checked: radius, visibility and the interaction source apply
```

A detector on a Node3D covers every mesh below it. When several detectors cover the clicked
mesh, all of them fire, in order of `priority` (higher first, default 0) and then creation order;
handlers run one after another (Lua has no parallel calls, and one failing handler does not stop
the others). A real press calls `press`, a release over the same object calls `release` and
`click`, and a release elsewhere or a camera drag calls `cancel`.

## Relation to `input.actions`

The built-in `Move`, `Look`, `Jump` and `Interact` still live in `input.actions`
(see `actions.md`) and drive the default character and camera. `InputMap` is the API for game
actions; both receive the same keyboard, gamepad and mouse events.

Gamepad rumble and sensors are in `katsa.gamepad` (see `gamepad.md`). Not included: a Workspace
editor for the map.
