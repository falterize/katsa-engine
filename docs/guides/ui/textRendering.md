# Text rendering

Menu, Workspace, inspector dialogs, Stats, example HUDs and world UI use the
same TextLabel/Button nodes and `source/engine/ui/drawing/text.lua`. Custom
widgets should use `ui:drawText(node)` instead of creating separate font paths.

## Physical glyphs, logical layout

Text sizes and UI geometry remain logical units. The shared `ui:rasterFont(size)`
returns a cached native Font and the scale converting physical glyph metrics to
logical units. Its point size is `round(size * ui.density)`, with a minimum of
one physical pixel. The Font itself uses DPI scale 1; drawing applies the inverse
density exactly once. This keeps glyph spacing and atlas coordinates on the
physical pixel grid at fractional display scales while retaining antialiasing.

Measurement, wrapping, size fitting, RichText and drawing all use these matching
metrics. Font-size fitting and retained Text buffers remain cached. Layout can
wrap slightly differently from older releases because it now measures the actual
physical glyphs rather than rounded logical metrics.

This avoids fractional-DPI metric/quad rounding in the legacy path.
`ui:font(size)` remains available with its legacy native Font/DPI semantics for
existing callers. New custom text rendering should use `ui:rasterFont(size)` and
its returned scale, or delegate to TextLabel.

`pixelGrid.lua` snaps paint origins without changing authored rectangles or input
coordinates. Translucent CanvasGroup renders into a physical-pixel target and
composites at a snapped origin. ViewportFrame uses an independently sized native
UI overlay; it does not lower or raise the 3D scene resolution to fix text.
Both paths retain ancestor clipping and stencil masks.

Do not set fonts to nearest filtering to compensate for a scale error: the stock
path keeps linear filtering and normal font hinting. Rotated/sheared labels,
explicit post effects, perspective world panels and deliberately low-resolution
targets can still be filtered by their transforms. Font glyph coverage remains
that of the bundled LÖVE default font.

## Shared widgets and routing

The UI hierarchy is World3D -> World2D -> CanvasGroup -> widgets. Workspace trees,
property editors, menus, popups, Stats charts and curve editors already follow
this hierarchy. Their specialized draw methods are node implementations, not
separate UI systems.

`VirtualJoystick` is a reusable Frame subclass in `source/engine/ui/nodes`.
`setAxes(x, y)` validates and normalizes finite axes, then invalidates paint only
when values change. The input adapter updates its layout and axes; it no longer
owns a custom paint component. Existing joystick hit regions and movement
bindings retain their behavior.

Screen UI, BillboardUI/SurfaceUI and ViewportFrame share the capture service in
`source/engine/input/uiCapture.lua`. Host adapters convert pointer coordinates;
the shared service distinguishes content panning, scrollbar dragging and widget
capture. See [scrolling](scrolling.md) for gesture semantics.
