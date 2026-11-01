# UI modifiers

The shared screen, BillboardUI and SurfaceUI renderer supports UICorner, UIStroke
and UIGradient. All use normal node lifetime and the owning UI hierarchy.

```lua
local label = ui:text(
    { position = { 0, 20, 0, 20 }, size = { 0, 200, 0, 80 }, text = 'Gradient', backgroundColor = {
        1,
        1,
        1,
    } },
    ui.content
)
ui:create('UICorner', { radius = { 0.1, 4 } }, label)
local stroke = ui:create(
    'UIStroke',
    { target = 'Border', thickness = { 0.01, 2 }, color = { 1, 1, 1 } },
    label
)
ui:create(
    'UIGradient',
    {
        offset = { 0.1, 4, 0, 0 },
        colorStops = {
            { time = 0, color = { 1, 0.2, 0.3 }, transparency = 0 },
            { time = 1, color = { 0.2, 0.8, 1 }, transparency = 0.7 },
        },
    },
    stroke
)
```

Thickness and Radius are Vector2 Scale/Offset against the smaller visual parent
side. Radius clamps to half that side. Border thickness clamps to 64 pixels;
Text to 8, with bounded glyph draws. UIGradient Offset is UDim2 against the content
area plus logical pixels. Alpha multiplies source/parent/group opacity and never
rewrites parent transparency. A parent gradient leaves its separate strokes alone;
a gradient under a UIStroke colors only that stroke, using the parent's rectangle.
Background/Text targets on strokes select the same stroke tint. Other modifier
nesting remains invalid. Custom visual material and gradient on the same element
are mutually exclusive; rounded ancestor/scissor clipping remains supported.

See [UI layout](uiLayout.md) for units and [Workspace](../editor/workspace.md) for inspector editing.
