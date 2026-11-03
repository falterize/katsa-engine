# ScrollFrame

ScrollFrame follows the engine's lowerCamelCase convention. Roblox-style aliases
such as `ScrollingDirection`, `CanvasPosition` and `CanvasSize` are also accepted.
The property model is based on the
[Roblox ScrollingFrame reference](https://create.roblox.com/docs/reference/engine/classes/ScrollingFrame),
with the engine's existing vertical behavior kept as the default.

```lua
local frame = ui:scroll({
    name = 'Inventory',
    position = { 0, 20, 0, 20 },
    size = { 0, 320, 0, 200 },
    scrollingDirection = 'XY',
    canvasSize = { 0, 640, 0, 480 },
    canvasPosition = { 0, 0 },
    automaticCanvasSize = 'None',
    scrollBarThickness = 6,
    horizontalScrollBarInset = 'ScrollBar',
    verticalScrollBarInset = 'ScrollBar',
}, ui.content)
```

| Property | Behavior |
| --- | --- |
| `scrollingDirection` | `X`, `Y` (default) or `XY`; disabled axes reset to zero |
| `scrollingEnabled` | Default true; false blocks user scrolling and hides bars, while programmatic offsets still work |
| `canvasSize` | UDim2 `{scaleX, offsetX, scaleY, offsetY}` relative to frame dimensions; nonnegative |
| `canvasPosition` | Vector2 logical-pixel scroll offset; clamped after layout |
| `automaticCanvasSize` | `None`, `X`, `Y`, `XY`; extends the authored canvas minimum to visible descendant extents |
| `absoluteCanvasSize` | Resolved Vector2 logical-pixel extent; reported read-only in Workspace |
| `absoluteWindowSize` | Resolved Vector2 viewport after scrollbar insets; reported read-only in Workspace |
| `horizontalScrollBarInset` | `None`, `Always`, `ScrollBar`; reserves space at the bottom |
| `verticalScrollBarInset` | `None`, `Always`, `ScrollBar`; reserves space at the selected side |
| `verticalScrollBarPosition` | `Left` or `Right` |
| `scrollBarThickness` | Logical-pixel thickness; zero hides bars |
| `scrollBarImageColor3`, `scrollBarImageTransparency` | Shared bar color and opacity |
| `topImage`, `midImage`, `bottomImage` | Image-path caps/middle; empty strings draw rounded solid parts. Horizontal bars rotate these parts |
| `contentPadding` | Extra pixels after measured content on automatic axes |

Dragging content pans the allowed axes: moving the pointer down reveals earlier
content, and moving right reveals content to the left. Dragging a scrollbar
thumb follows the pointer instead: down/right increases the corresponding
canvas offset. Thumb travel maps to the full scroll range while preserving the
grab offset. Clicking the track centers the thumb at the pointer and begins a
bar drag; movement outside the frame clamps to the ends.

Bars hit-test above overlapping children, including with no inset. Invisible or
disabled bars do not intercept input. Content buttons defer their press until a
tap is confirmed; panning or dragging on a disabled axis does not click them.
Horizontal Slider drags and explicit `dragCapture` widgets retain ownership.
The same capture rules apply to screen UI, world panels and ViewportFrame.

Vertical wheel input scrolls Y; on an
X-only frame it scrolls X. Horizontal wheel input scrolls X. Hold Shift to map the
vertical wheel to X on an XY frame. The UI Gallery contains a two-axis tile canvas
with a button to cycle its allowed directions.

Hidden nodes and modifiers do not extend automatic canvas bounds. A clipping child
contributes its own rectangle; unclipped visible descendants can extend it. Canvas
measurements and layout snapshots are reused until relevant geometry or properties
change. Insets and child clipping use the same resolved window dimensions.

Legacy `length`, `automaticLength`, `scrollY` and `scrollX` remain available.
`length` edits the Y pixel offset of canvasSize. `automaticLength = true` preserves
the old measured-height behavior, including shrinking; prefer automaticCanvasSize
for new two-axis layouts. Editing automaticLength switches automaticCanvasSize to
Y or None. Direct canvas component edits win if both a legacy scalar and its
canvas counterpart are changed before layout. Scroll state is synchronized during
layout; use `ui:layout()` before reading resolved values after an edit.

`ui:scrollBy(frame, deltaY, deltaX)` preserves the old vertical argument order.
`ui:wheel(pointerX, pointerY, wheelY, wheelX)` accepts an optional horizontal delta.
The shared inspector exposes all new properties and direction/inset options.

This API does not implement elastic overscroll, inertia, network replication or
Roblox Content objects; these are not exposed as nonfunctional settings.

## Swipe feel: inertia, elastic ends, mouse swipe

| Property | Default | Meaning |
| --- | --- | --- |
| `inertia` | 0.6 | How far the content glides after a swipe. 0 stops dead, 1 glides long. |
| `overscroll` | 0.25 | Rubber-band stretch past the ends, as a fraction of the window. 0 is a hard stop. |
| `bounceSpeed` | 14 | How fast the stretch springs back (per second); shown when `overscroll` > 0. |
| `dragWithMouse` | false | Lets the mouse swipe the content. Touch always swipes; the wheel and the scrollbar thumb work regardless. |

A flung frame that reaches an end keeps its speed into the stretch and springs back. The wheel and `scrollBy` stop any glide and are always instant.
