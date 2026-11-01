# Render quality

Renderer properties are editable in Workspace Lighting / Render. `renderDensity`
uses the device DPI scale by default (clamped to 1..3); `msaa` defaults to 2 on desktop, except Intel UHD (0); mobile also defaults to 0.
Intel UHD retains the fastest native-resolution path to preserve frame rate.
MSAA smooths geometry edges at additional GPU cost. Set it to 0 for the fastest
native-resolution path or 4 for stronger edge smoothing.
`actualMSAA` reports the accepted value. Canvas capabilities and color/depth
binding are checked before replacing existing targets. Unsupported combinations
fall back to zero MSAA.

`maxRenderPixels` defaults to 8,294,400 on Windows/Linux/macOS and 4,194,304
elsewhere; `maxRenderBytes` defaults to 402,653,184. The latter
limits an estimate of color/depth and resolve storage, not total driver memory.
The planner reduces MSAA and then resolution to fit. Raising budgets can improve
quality at a real memory/render cost. Shadows and world-UI canvases have separate
limits. Resolution and MSAA improve geometry edges; they cannot fix a physically
tiny panel or inadequate source image resolution. BillboardUI `canvasSize` is in
logical UI pixels, and its existing adaptive canvas density remains bounded.
Screen UI fonts use exact target density, including fractional DPI; text origins
are snapped to physical target pixels without changing layout/hit rectangles.

See `katsa.graphics.newCanvas`, `Canvas:getMSAA` and `Texture:getDPIScale`. Actual accepted MSAA
can differ from the requested count. No phone frame-rate gain is claimed.


## Windows display scaling

Startup enables per-monitor-v2 DPI awareness before the first window is created.
An unaware LÖVE host can otherwise be bitmap-scaled by Windows at 125% or 150%,
softening the whole image and every font. Older Windows uses system awareness as
a fallback. This affects only the game process; it does not change desktop scaling
or modify the LÖVE installation. A fused custom executable should also declare DPI
awareness in its application manifest, as recommended by
[Microsoft](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setprocessdpiawarenesscontext).

Windows SDL may report a graphics DPI scale of 1 while returning native-pixel
window dimensions. Do not multiply render density by Windows' 125% setting again:
that would add supersampling on top of the native framebuffer.

UI layout applies the monitor-to-graphics-DPI ratio separately. At Windows 125%,
48 logical UI units become 60 native pixels, with fonts rasterized at that density.
The initial 1280x720 logical window is scaled to the system DPI and clamped to the
work area; at 125% it normally opens at 1600x900 native pixels. Monitor changes
refit screen UI. This preserves readable control sizes without bitmap stretching
or increasing the 3D render density. See [responsive UI](../ui/uiLayout.md).

UI font density may be below 1 when a reference layout is fitted to a smaller
window. Glyphs are rasterized at that actual target density instead of rendering
large and then shrinking. Retained plain-text lines snap their aligned origins to
physical pixels. UI post-effect canvases inherit their actual target DPI, including
world-UI targets, instead of using the screen DPI by accident.

Linear image variants generate mipmaps and use up to 8x supported anisotropy for
stable distant/oblique textures. Explicit pixel-art variants keep nearest filtering
and no mipmap filtering. Source asset resolution still limits visible detail.


Stock UI text now uses cached physical-pixel fonts through `ui:rasterFont`, with
logical measurements and one inverse draw scale. The legacy `ui:font` API is
retained for compatibility. Translucent groups and viewport overlays use native
pixel targets to avoid a second resampling step. See [text rendering](../ui/textRendering.md)
for the shared implementation and its transform limits.
