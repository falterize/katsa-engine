# Sound nodes in v46

World3D.audio must be assigned before creating these nodes. Game.load already
assigns the scene Audio scope; creating an independent World3D requires doing so
explicitly. Audio:update drives a flat sound/effect index, not the Workspace tree.

```lua
local music = world:create('SoundGroup', {
    name = 'Music',
    volume = 0.7,
})
local sound = world:create('Sound', {
    name = 'Chime',
    group = music,
    resource = 'assets/audio/effects/effectProbe.wav',
    spatial = true,
    volume = 0.8,
    playbackSpeed = 1,
    looped = true,
    minDistance = 20,
    maxDistance = 300,
}, speaker)
world:create('SoundReverb', { decaytime = 1.8, gain = 0.35 }, sound)
sound:play()
```

## Playback and ownership

Sound exposes play(), pause(), stop(), isPlaying(), seek(seconds), tell(). Play
resumes a paused loaded voice; stop releases it. SoundPitch children multiply
playbackSpeed, with total rate capped at 8. Positive finite rates are required.
Pitch changes both pitch and playback duration, not independent time stretching.

Sound resource is a LÖVE-supported audio path. stream=true uses streaming for
long recordings; static sample data is cached in the scene's existing Audio
scope and voices clone it. Cache data is released with the scene, not on each
stop. Stop/play after changing resource, stream or spatial mode. looped, gain,
pitch and distance changes affect existing voices. Missing resources fail with
the existing asset error; no silent replacement asset is invented.

Sound is a Node, not Node3D: it follows its nearest spatial ancestor's world
position and orientation through Folders. A spatial source requires a Node3D
ancestor; detaching it stops playback. Reattaching requires play(). Attachment3D
scale follows the common transform API. No skeleton/socket importer exists yet.
The active camera supplies the shared listener. Existing engine-to-OpenAL axes,
rolloff and stereo-emitter behavior are retained. Distance uses engine world
units. Default rolloff is LinearSquare; the other supported modes are Linear and Inverse. Spatial mono recordings are recommended.

SoundGroup has volume (0..1) and muted. Sound.group optionally refers to a live
same-scene SoundGroup; otherwise the nearest ancestor group is used. Nested group
gains multiply, followed by Sound.volume and the existing master gain. Destroying
an explicit group stops referencing sounds and clears their group reference.
Cross-scene/mixer transfers are rejected before hierarchy mutation. Destroying a
parent releases child sources, effect sends and registrations. Scene/focus pause
preserves manually paused voices; resume does not restart those voices.

## Effects

Effects must be direct children of Sound or SoundGroup, including through ordinary
World3D:create. They have enabled, volume and a read-only diagnostic status. Native
settings below use LÖVE's names, not an invented DSP API.

| Node | Important settings | Processing |
| --- | --- | --- |
| SoundReverb | gain, decaytime, density, diffusion | Native reverb wet send |
| SoundEcho | delay, tapdelay, damping, feedback, spread | Native echo wet send |
| SoundChorus | waveform, rate, depth, feedback, delay | Native chorus wet send |
| SoundDistortion | gain, edge | Native distortion wet send |
| SoundPitch | playbackSpeed | Source playback rate multiplier |
| SoundFilter | filterType, highgain, lowgain, volume | Dry Source filter |

Root group effects precede descendant group effects, then direct Sound effects,
in child order. Native wet effects are parallel sends added to the dry signal;
this ordering controls limited send assignment, **not serial signal processing**.
At most the device's getMaxSourceEffects() sends are attached to each source.
Unsupported/rejected definitions or sends retain dry playback and report status.
Definitions/settings are cached; unchanged frames do not recreate native effects.
SoundFilter accepts lowpass/highpass/bandpass; the last enabled nearest/direct
filter wins. highgain/lowgain are normalized gain controls, not cutoff Hz.

SoundGroup effects share a native effect slot. Shared reverb/echo tails can persist
until decay when one sound stops; destroying/disabling the effect removes its
slot. Stop removes a Sound's own direct native effects. Muted groups silence their
shared wet returns; scene pause does likewise. Per-source independent tails,
serial group buses and seamless effect crossfades are not implemented.

The listening lab has Dry, Reverb, Echo, Chorus, Distortion, Low pitch, High pitch,
Low-pass and Group reverb presets. Click a preset to start; playback is not
automatic. Its three-second mono probe includes silence so tails are audible.
The probe was generated for this release; no third-party library/audio was added.

Primary API references: https://love2d.org/wiki/katsa.audio.setEffect,
https://love2d.org/wiki/katsa.audio.isEffectsSupported,
https://love2d.org/wiki/katsa.audio.getMaxSourceEffects,
https://love2d.org/wiki/Source:setEffect,
https://love2d.org/wiki/Source:setFilter,
https://love2d.org/wiki/Source:setPitch.
