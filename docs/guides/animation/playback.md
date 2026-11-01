# Playing and Enabled

Both lowercase `playing/enabled` and `Playing/Enabled` assignments are supported.
Properties are mediated by the node API, so assignments take effect immediately.

| Node | Playing = false | Playing = true | Enabled = false |
| --- | --- | --- | --- |
| Sound | Pause the source | Play/resume it | Set dry gain to zero and disconnect effect sends; playback continues |
| Ramp, Animated | Pause and retain values | Restart playback from time zero | Advance time but suppress target writes |

Sound play/pause/stop/seek/tell remain available. Stop releases its voice; Playing true
loads it again. Enabled true restores current gain immediately. Sound effects and
platform audio output still depend on device/OpenAL support. Null-audio validation
checks source state/gain, not audible output or effect tails on a physical device.

Animated Ramp play/stop/pause/resume remain available. Explicit resume continues
elapsed time; Playing true restarts. Enabled true immediately applies the current
sample when a track exists. It never changes the target's Enabled/Transparency.
Completion sets Playing false. Static Ramp has no Playing inspector field; its
Enabled switch disables application of its gradient/property effect.

```lua
ramp.Playing = true
ramp.Enabled = false -- Timeline continues, target holds its last applied values.
ramp.Enabled = true -- Apply the current timeline sample.
ramp.Playing = false -- Pause.
ramp.Playing = true -- Restart, unlike ramp:resume().
sound.Playing = true
sound.Enabled = false -- Inaudible while the source keeps running.
```

The Ramp/Tween and Sound example panels demonstrate these switches separately.
