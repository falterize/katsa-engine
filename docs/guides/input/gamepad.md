# Gamepads, vibration and gyro

`katsa.gamepad` wraps the SDL game controller API. Xbox, PlayStation, Switch and generic pads
share one layout, so scripts only see the names below.

```lua
local pad = katsa.gamepad.first()           -- oldest connected pad, or nil
if pad then
    pad:isDown('a')                         -- any of several buttons: pad:isDown('a', 'b')
    pad:getAxis('leftx')                    -- sticks -1..1 (up/left negative), triggers 0..1
    pad:setVibration(0.5, 1, 0.3)           -- low motor, high motor, seconds
    pad:setSensorEnabled('gyro', true)
    local x, y, z = pad:getSensor('gyro')   -- rad/s; nil while off or missing
end
```

- Buttons: `a b x y back guide start leftstick rightstick leftshoulder rightshoulder dpup dpdown
  dpleft dpright misc1 paddle1..paddle4 touchpad`.
- Axes: `leftx lefty rightx righty triggerleft triggerright`.
- Events (scene callbacks, each receives the pad object): `gamepadadded`, `gamepadremoved`,
  `gamepadpressed(pad, button)`, `gamepadreleased(pad, button)`, `gamepadaxis(pad, axis, value)`.
- `setVibration(low, high, seconds)` returns false when the pad cannot rumble; a new call replaces
  the running one and `setVibration(0, 0)` stops it. `setTriggerVibration` drives the impulse
  triggers of Xbox One and Series pads.
- Sensors: `'gyro'` and `'accel'`; check `pad:hasSensor(kind)` first.

## Scene input

The first pad drives the scene input: the left stick walks, the right stick looks (radial deadzone
0.2) and buttons feed the named actions through `gamepad = '<button>'` bindings (`Jump` is `a`,
`Interact` is `x`). Start opens the pause menu. Other pads are read through `katsa.gamepad`.

## Requirements

Rumble needs SDL 2.0.9 and sensors SDL 2.0.14. With an older `SDL2.dll` those calls return
false/nil instead of failing.
