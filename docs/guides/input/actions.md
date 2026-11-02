# Scene-owned input actions

Each `Input.new(scene, controls)` owns `input.actions`. Values use existing numeric
vector tables; no additional vector math API is introduced.

| Action | Value / units | Default adapter |
| --- | --- | --- |
| Move | `{right, up, forward}`, normalized horizontal magnitude <= 1 | WASD and joystick; Q/E vertical Free camera |
| Look | `{dx, dy}`, logical safe-area pixels accumulated for this update | Captured camera pointer; follow camera uses followSensitivity |
| Jump | held boolean plus consumed press edge | Space or `input:trigger('Jump')` |
| Interact | held boolean plus consumed press edge | F or `input:trigger('Interact')`; center ray ClickDetector |

```lua
scene.input.actions:bind('Jump', { key = 'j' })
scene.input.actions:bind(
    'Move',
    { left = 'a', right = 'd', forward = 'w', back = 's', up = 'e', down = 'q' }
)
scene.input.actions:on('Jump', function(scene)
    scene.character:jump()
end)
scene.input.actions:on('Move', function(scene, direction, dt)
    scene.character:setMove(direction[1], direction[3])
end)
scene.input.actions:on('Interact', function(scene)
    -- Scene gameplay interaction; overrides the default center-ray adapter.
end)
```

`actions:on` installs one adapter per action. Move runs each input update; Look
runs when a delta exists; Jump/Interact run once per queued edge. `trigger` coalesces
multiple requests before one update. `value(name)` returns the current value;
`consume(name)` removes a queued edge. Do not consume edges before Input:update if
using its default/custom adapters. Forward keyboard events with `input:keypressed`
and `input:keyreleased`; do not poll the operating system's held keys in gameplay.

World interaction retains explicit world.interactionSource or detector.positionSource,
Radius, nearest-hit occlusion and UI blocking. A pointer click remains supported.
Joystick, camera and UI own distinct pointer IDs until release/cancel. Vertical scroll
gestures can transfer from labels/buttons/sliders; a transferred gesture never clicks
the old target. `input:cancel(id)` cancels only that pointer. `input:reset()` clears all
pointers, held keys and queued actions on focus loss, suspension and scene transitions.
katsa has touchreleased, not a separate touchcancelled callback; integrations with
an explicit cancellation event should call `input:cancel(id)`.

Workspace → Lighting / Render → Mobile input / Joystick edits radius and center in
logical safe-area pixels. Authored values persist on resize and clamp to the viewport;
unmodified defaults adapt proportionally. Free cameras use sensitivity in degrees
per logical pixel; follow cameras use their own followSensitivity. Real device
multitouch and suspension remain to be checked on Android.

## On-screen joystick in every scene

Collection scenes share the common input layer: a joystick at the bottom-left and a camera drag area.
A scene's own widgets win a touch over the joystick, so after the second frame the scene runtime
moves the joystick to the nearest spot no widget covers (`Game:clearJoystickSpot`). Scenes whose UI
fills the whole bottom area (galleries, viewport demos) hide it instead. `validation/tests/versions/v108_4/mobileControls.lua`
presses the joystick in every catalog scene.
