# Responsive UI

The engine uses lowerCamelCase properties. UI coordinates are logical pixels;
LÖVE/device DPI determines physical pixels. A new ScreenUI defaults to
`layoutMode = 'Viewport'`: call `ui:fit(windowWidth, windowHeight)` on resize.
The safe viewport becomes ui.width/ui.height after conversion to logical units.
On Windows, Viewport uses the monitor scale divided by LÖVE graphics DPI, so SDL
native-pixel coordinates do not make controls smaller at 125% or 150%. A 48-unit
button occupies 60 physical pixels at 125%. Font rasterization and hit-testing use
the same conversion. Platforms already exposing logical coordinates retain their
normal DPI path without a second scale. Moving between Windows monitors refits UI
when the DPI changes. Relative UDim2 sizing adapts to different aspect ratios;
consistent logical control sizes do not force identical layouts on every screen.
Existing Menu/Game/Pause scenes explicitly retain `Fit`, which
maps a 1280x720 reference canvas into the safe area. The UI gallery uses Viewport.
Do not confuse reference pixels in Fit with physical display pixels.

```lua
local frame = ui:create('Frame', {
    position = UI.udim2(0.5, 0, 0.5, 0),
    size = UI.udim2(0.7, -20, 0.5, 0),
    anchorPoint = { 0.5, 0.5 },
    relativeTo = 'XY',
    backgroundColor = { 0.08, 0.12, 0.2 },
    backgroundTransparency = 0.15,
}, ui.content)
```

UDim2 is `{scaleX, offsetX, scaleY, offsetY}`. Scale 0..1 covers 0..100% of the
immediate parent's resolved dimensions (the viewport at the root); finite values
outside that interval are also permitted for deliberate overflow. Offset is
added after scale. AnchorPoint chooses the widget pivot as fractions of its own
resolved width/height, usually 0..1; default is `{0,0}` for widgets.

relativeTo is XY, XX or YY. XY uses parent width for X and height for Y; XX uses
parent width for both; YY uses parent height for both. `sizeRelativeTo` and
`positionRelativeTo` override the shared mode independently. Applying this choice
to position is an engine extension; Roblox's SizeConstraint specifically concerns
size. This is a layout convention, not replication of its scene architecture.

ScreenUI, BillboardUI and SurfaceUI **children** use the same UDim2 layout, text,
modifiers, clipping and input system. BillboardUI root Position/Offset are Vector3;
Size and CanvasSize are UDim2, and AnchorPoint is Vector2. Screen-mode Size resolves
against viewport logical dimensions; World3D-mode BillboardUI Size Scale uses local
support dimensions, and its Offset is in world units. CanvasSize scales against
resolved Size pixels (World3D Size times canvasPixelsPerUnit). SurfaceUI/Decal
Position and Size resolve against the selected local surface. See the surface guide
for the full conversion table and explicit panel/anchor shift composition.

## Color and opacity

- backgroundColor/backgroundTransparency control the element fill.
- imageColor/imageTransparency control ImageLabel content independently.
- textColor/textTransparency control text independently.

New colors are normalized RGB triples; transparency is 0..1 (1 is invisible).
Legacy RGBA color/tint/textColor and x/y/width/height still work. Explicit new
channels override their legacy counterparts. `transparency` remains an optional
legacy whole-element multiplier; CanvasGroup transparency composites its subtree
once. New channels do not change hit-testing. Use visible/enabled and capture to
control interaction. UIGradient stop transparency can be supplied separately from
RGB, while legacy RGBA stops remain supported.

## Text

textScaled fits text within the label's padded resolved bounds. minTextSize
(default 8) and maxTextSize (default 72) constrain the logical font size (1..200).
If text cannot fit at the minimum, it is clipped. Scaled/rich layouts are cached
until content, bounds, size limits or density change. Rich text uses glyph-based
wrapping; ordinary unscaled labels retain the existing LÖVE printf wrapping.

richText enables a documented subset: `<b>`, `<i>`, `<u>`, `<s>`, `<br/>`,
`<font color="#RRGGBB" size="28">` and closing tags. Entities &lt;, &gt;, &amp;,
&quot; and &apos; are decoded. Bold is a bounded emboldened draw; italic is a
sheared draw using the same font. Arbitrary font faces, stroke tags, full Roblox
markup compatibility and automatic localization are not implemented. Unknown
markup is literal; malformed supported nesting raises a clear error. Labels are
limited to 64 KiB of markup and 32 nested levels. No code is evaluated.

```lua
ui:create('TextLabel', {
    size = { 1, 0, 0, 80 },
    textScaled = true,
    richText = true,
    text = '<b>Ready</b> <font color="#55CCFF">player</font>',
    textColor = { 1, 1, 1 },
    textTransparency = 0,
    backgroundTransparency = 1,
}, frame)
```

Mouse hover exposes enter/leave/hover events and onEnter/onLeave/onHover handlers.
Touch retains independent captures and press/move/release/cancel. The routing
order is screen UI, reserved joystick, world UI, then camera look. A captured
world panel keeps local UI coordinates through release; focus loss cancels it.

Primary conventions:
https://create.roblox.com/docs/reference/engine/enums/SizeConstraint
https://create.roblox.com/docs/ui/position-and-size
https://love2d.org/wiki/Texture:getDPIScale

## Reference semantics

The four components and anchor semantics follow [Roblox UDim2](https://create.roblox.com/docs/reference/engine/datatypes/UDim2), [UI positioning](https://create.roblox.com/docs/ui/position-and-size) and [SizeConstraint](https://create.roblox.com/docs/reference/engine/enums/SizeConstraint). Roblox SizeConstraint applies to size; the independent position-relative setting is this engine's extension.

See [ScrollFrame](scrolling.md) for X/Y/XY scrolling, canvas dimensions and scrollbar insets.


See [text rendering and shared widgets](textRendering.md) for physical-pixel glyphs,
CanvasGroup/ViewportFrame density and the common input capture path.
