# SoundManager, AudioListener and AudioSource (v108.1)

Three modules separate the roles that `Sound` used to combine. Existing `Sound` and `SoundGroup` scenes keep working.

| Module | Role | File |
| --- | --- | --- |
| `SoundManager` | Mix control and bookkeeping for a scene's audio | `engine/audio/manager.lua` |
| `AudioListener` | Where the scene is heard from | `engine/nodes/audio/audioListener.lua` |
| `AudioSource` | A Node3D that emits sound from its own transform | `engine/nodes/audio/audioSource.lua` |

## SoundManager

Every Audio scope owns one manager, `scene.audio.manager`. It stores nothing itself: volumes and mute flags
live in the scope's group table, so Sound nodes, AudioSources, direct `audio:play` calls and the UI share one mix.

```lua
local sound = scene.audio.manager
sound:setMasterVolume(0.6)
sound:createGroup('vehicles', { volume = 0.5, parent = 'effects' })
sound:setGroupMuted('music', true)
local gain = sound:getGroupGain('vehicles') -- master * effects * vehicles, 0 when any ancestor is muted
local voice = sound:play('assets/audio/effects/hit.wav', { group = 'vehicles' }) -- fire and forget
sound:pauseAll(); sound:resumeAll(); sound:stopAll()
```

`getVoiceCount()`, `getGroupNames()`, `isMuted()` and `isPaused()` report state. Volumes outside 0..1 and unknown
groups raise errors instead of being clamped silently.

## AudioListener

A Node3D with `enabled`. While at least one enabled AudioListener exists, the first one in creation order replaces
the camera as the listener: position, +Z forward and +Y up are sent to OpenAL (Z mirrored, as for the camera) and
distance attenuation is measured from it. Disabling or destroying it hands the role to the next enabled listener, then
back to the camera. `manager:getActiveListener()` returns the current node or nil.

## AudioSource

A Node3D with the full Sound API: `resource`, `volume`, `playbackSpeed`, `looped`, `stream`, `minDistance`,
`maxDistance`, `rolloff`, `stereoWidth`, `group`, `play/pause/stop/seek/tell`, effect children (`SoundReverb`, ...). It is
`spatial` by default and emits from its own world transform, so it works directly under Folders, Meshes and Attachments
without a helper Attachment3D. `isA('Sound')` is true, so effects, groups and the inspector treat it as a Sound.

```lua
local engine = world:create('AudioSource', {
    resource = 'assets/audio/effects/engine.wav',
    position = { 0, 1, 0 },
    looped = true,
    minDistance = 10,
    maxDistance = 200,
}, car)
engine:play()
```

Verification: `katsa . --test-v108.1` runs 30 audio checks against instrumented katsa audio (routing, attenuation, listener
selection, lifetime). It does not test audible output.

## Live audio: capture and queue playback

`katsa.audio` also has the pieces voice chat uses (`source/katsa/audio/stream.lua`):

```lua
local mic = katsa.audio.openCapture(12000)       -- mono 16-bit; nil, reason without a microphone
mic:start()
local pcm, count = mic:read()                    -- int16 cdata + samples recorded since last read
mic:stop(); mic:close()

local voice = katsa.audio.newQueueSource(12000)  -- gapless queue, 3D like any Source
voice:queue(pcm, count)
voice:setPosition(x, y, z); voice:setVolume(0.8)
voice:getQueued()                                -- buffers waiting (use it to cap latency)
voice:release()
```

With the null driver (servers, tests, `KATSA_AUDIO=null`) `openCapture` returns nil and the queue
source swallows data. `source/engine/audio/muLaw.lua` compresses 16-bit samples to one byte
(`MuLaw.encode(samples, count)` / `MuLaw.decode(bytes)`), enough for speech at 8-16 kHz.
