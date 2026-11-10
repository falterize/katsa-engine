# InputMap: named actions

`scene.input.map` (an `InputMap`, `source/engine/input/inputMap.lua`) lets gameplay ask for an
action by name instead of a device. Keys, mouse buttons, the wheel, gamepad buttons and gamepad
axes all feed the same actions, and a binding is plain text, so it can be changed at run time
and saved.

```lua
local map = scene.input.map
map:action('jump', { 'key:space', 'pad:a' })
map:action('left', { 'key:a', 'axis:leftx-' })
map:action('right', { 'key:d', 'axis:leftx+' })
map:action('fire', { 'mouse:1', 'axis:triggerright+' })

-- in update:
if map:pressed('jump') then character:jump() end
local x = map:axis('left', 'right')          -- -1..1
character:setMove(x, map:axis('back', 'forward'))
```

## Events

One string per event; a bare name is a key.

| Event | Meaning |
| --- | --- |
| `key:space`, `key:a`, `key:lshift` | Keyboard key (names as in `katsa.keyboard`) |
| `mouse:1` | Mouse button number (1 left, 2 right, 3 middle) |
| `wheel:up`, `wheel:down` | One wheel notch (a momentary press) |
| `pad:a`, `pad:leftshoulder` | Gamepad button (names in the gamepad guide) |
| `axis:leftx+`, `axis:lefty-`, `axis:triggerright+` | A gamepad axis moving in that direction |

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
| `map:pressed(name)` / `map:released(name)` | True for the one update after the edge, even for a tap shorter than a frame |
| `map:strength(name)` | 0..1; keys give 1, an axis gives its travel past the deadzone, rescaled |
| `map:axis(negative, positive)` | `strength(positive) - strength(negative)` |
| `map:vector(left, right, up, down)` | `x, y`, length at most 1 |
| `map:on(name, fn, phase)` | Calls `fn(name)` on `'pressed'` (default) or `'released'`; returns a function that removes it |

`deadzone` (default 0.2, per action) is how far an axis must travel to count as down.
Reading an action that was never defined is an error, so a misspelt name does not silently
read as "not pressed". Edges are published at the start of `Input:update`, before the scene
script runs.

## Editing bindings

```lua
map:bind('jump', 'key:w')      -- add an event
map:unbind('jump', 'pad:a')    -- remove one
map:action('jump', { 'key:j' })-- replace all events (keeps the deadzone unless you pass one)
map:clear('jump')              -- keep the action, drop its events
map:remove('jump')
map:events('jump')             -- copy of the event strings
```

### Rebinding screen

`map:listen(callback)` waits for the next pressed event (key, button, wheel, axis) and hands it
to `callback(event)`; no action sees that event. Use it after the player clicks "change":

```lua
map:clear('jump')
map:listen(function(event) map:bind('jump', event) end)
```

### Saving

```lua
local data = map:toData()   -- { jump = { 'key:space', 'pad:a' }, aim = { events = {...}, deadzone = 0.4 } }
map:load(data)              -- defines every action in data; others stay as they are
```

Store `data` with the save system (`source/engine/persistence`) and load it right after the
scene starts. The map belongs to one scene's `Input`; to share one set of bindings between
scenes, save and load them. A standalone map works too: `InputMap.new(data)` and feed it with
`map:setEvent(event, strength)` and `map:update()`.

## Pressing from code (on-screen buttons, tests, scripted input)

Every input path can be driven by code, so a touch layout needs nothing special.

| Goal | Call |
| --- | --- |
| Hold a named action | `map:press(name, strength)` ... `map:release(name)` |
| Press and release at once | `map:trigger(name)` (also `input:trigger(name)`) |
| Fake a device event | `map:setEvent('key:space', 1)` then `0`; `map:tap('wheel:up')` |
| Tap a UI node | `input:click(node)` (press and release at its centre) |
| Hold a UI node | `input:press(id, input:nodeCenter(node))` ... `input:release(id, x, y)` |
| Tap a screen point | `input:tap(x, y)`: reaches UI, billboard UI and ClickDetector3D meshes under it |
| Fire a ClickDetector3D | `detector:activate(pointerId)`, or `detector:activate(pointerId, true)` to skip the distance and visibility checks |

```lua
-- A touch button that holds "sprint" while it is pressed.
button:on('press', function() scene.input.map:press('sprint') end)
button:on('release', function() scene.input.map:release('sprint') end)
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
