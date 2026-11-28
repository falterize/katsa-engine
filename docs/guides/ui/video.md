# VideoFrame

`VideoFrame` plays a video file inside UI. It is a normal `UINode`: layers, `clip`, `UICorner`,
transparency and uiStyler work unchanged, and it works on screen UI, `BillboardUI` and `SurfaceUI`.

```lua
local video = ui:video({
    name = 'Intro',
    source = 'scene://video/intro.mp4',
    size = { 1, 0, 1, 0 },
    looped = true,
})
```

## Properties

| Property | Meaning |
| --- | --- |
| `source` | File path (`scene://`, `shared://` or a plain path). Changing it reloads. |
| `playing` | Plays while true; pauses while false. Default true. |
| `looped` | Restart at the end. Emits `looped` instead of `finished`. |
| `volume` | 0..1. |
| `speed` | 0.1..4. Any speed other than 1 mutes audio. |
| `time` | Playback position in seconds (writable: seeks). |
| `duration`, `status` | Read only. `status` is `ready`, `playing`, `finished` or `error`. |
| `fitMode` | `Fit`, `Crop` or `Stretch`. |

A video that cannot be opened draws the diagnostic checker and logs the reason; it never raises
from a render callback. A video that is not drawn (hidden, off screen, panel out of range) pauses.

## Formats and requirements

Decoding uses FFmpeg (libavformat, libavcodec, libswscale, libswresample, libavutil, 5.1 or newer)
loaded as shared libraries through FFI, so MP4, MOV, MKV, WebM, AVI, OGV and the usual codecs
(H.264, H.265, VP8, VP9, AV1, Theora, MPEG-4) work when the libraries are present. Use LGPL
builds. H.264 and H.265 are patent-encumbered; VP9, AV1 and Theora are free. Files inside
archives are copied to `video-cache/` first.

Decoding runs on a worker thread into a ring buffer; audio goes through an OpenAL queue and its
played time is the master clock (wall clock when there is no audio device).

## Not done yet

Theora fallback without FFmpeg, a YUV to RGB shader, a `SurfaceAppearance3D` video texture and
Android/iOS backends. Not verified outside Linux: Windows DLL layout, macOS, Android, real audio.
