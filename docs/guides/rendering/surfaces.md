# SurfaceUI and Decal

Both are scene-owned spatial nodes with validated parent, shared lifecycle,
Workspace and automatic cleanup. Parent them directly to Mesh3D, Attachment3D or
another Node3D, or use an independent same-World3D Adornee. A Folder can own an
adornment with explicit Adornee. Non-Mesh3D supports use the explicit supportSize
virtual box. Ownership cannot cross Worlds.

## Local faces

| face | Outward local normal | Image right / up |
| --- | --- | --- |
| Front | -Z | +X / +Y |
| Back | +Z | -X / +Y |
| Left | -X | -Z / +Y |
| Right | +X | +Z / +Y |
| Top | +Y | +X / +Z |
| Bottom | -Y | +X / -Z |

The engine's gameplay forward remains +Z. Face names define the parent's local
bounding-box sides independently of gameplay forward. Mesh3D faces use source
geometry bounds multiplied by Mesh3D.size, then the parent's spatial world pose.
Parent rotation, movement and scale are inherited; dimensions stay separate from
spatial scale. spatialPosition/rotation add a local face-frame pose; Position/Size use UDim2
surface layout. There is no independent surface Scale property.
surfaceOffset (default 0.03) separates it from the face in parent local units.
zIndex adds a small bounded separation and orders overlapping equal-depth panels.

These are rectangular planes, not curved projection or UV-aware mesh decals.
Arbitrary imported Mesh3D.localMatrix/vertex-deformed geometry is not automatically
followed by bounding faces. Use Attachment3D with explicit extents and a matching
pose for complex models. Bone sockets remain a future skeletal-animation feature.

## SurfaceUI

```lua
local panel = world:create('SurfaceUI', {
    name = 'Terminal',
    face = 'Front',
    canvasSize = { 0, 512, 0, 256 },
    surfaceOffset = 0.03,
    interactable = true,
    onTop = false,
}, box)
panel.ui:create('Button', {
    position = { 0.5, 0, 0.5, 0 },
    size = { 0.8, 0, 0.4, 0 },
    anchorPoint = { 0.5, 0.5 },
    text = 'Activate',
    textScaled = true,
    backgroundColor = { 0.1, 0.3, 0.5 },
    onPress = function()
        print('Activated')
    end,
}, panel)
```

Size UDim2 defaults to filling the selected face. Match CanvasSize aspect ratio
to physical Size to avoid stretched glyphs. CanvasSize is UDim2 relative to
physical Size times canvasPixelsPerUnit, with pixel offsets. Pixel-only CanvasSize
keeps authored layout stable. UI coordinates stay logical canvas pixels. UDim2, anchors,
relative modes, rich/scaled text, CanvasGroup, UICorner, UIGradient and both
UIStroke targets use the shared UI path. The plane clips canvas overflow rather
than silently resizing the physical surface. Canvas resolution/density is capped
by the device/maximum texture size and refreshes only for UI changes or density.

visible hides the inherited subtree; enabled disables interaction while retaining
rendering. interactable controls picking; transparency, maxDistance (default 500),
zIndex and layers control display. Panels are unlit like BillboardUI. By default
onTop=false and doubleSided=false: actual depth testing and geometry ray occlusion
apply, and the back face does not display or pick. doubleSided=true permits the
naturally mirrored back view. onTop=true bypasses world depth/occluders for display
and input, but preserves face orientation, limits and higher-priority screen UI.

Mouse/touch rays intersect the actual transformed panel and map to canvas
coordinates. Press, captured move, release, cancellation and hover use those
coordinates; leaving the rectangle preserves capture until release. A parallel
or invalid/back-facing release ray cancels rather than supplying invalid coordinates.
UI siblings follow draw ordering. No physical collider is required for a panel;
world occlusion uses visible triangle geometry. Very complex mesh picking can be
costly; acceleration for arbitrary imported meshes is future work.

## Decal

```lua
local tile = world:create('Mesh3D', {
    name = 'FloorTile',
    position = { 0, 0.5, 0 },
    size = { 30, 1, 30 },
    texture = 'white',
})
world:create('Decal', {
    name = 'Litter',
    face = 'Top',
    image = 'assets/textures/ui/litter.png',
    mode = 'Decal',
    unlit = false,
    transparency = 0,
}, tile)
```

Decal.image is an asset path or resource alias. Mode Decal places one image.
Texture repeats with textureSize/textureOffset in physical surface/world units.
Tiles uses FitMode and an area-relative Tile grid: tileSize is UDim2 against the
region's logical dimensions (physical size times canvasPixelsPerUnit), and
TileOffset is pixels. The modes retain settings on switching and expose only
applicable fields. Pixel selects a separate nearest-filter resource variant.
imageRotation is degrees; color is normalized RGB; transparency is 0..1.
Transparent texels reveal the parent. See the UI layout guide for units, transform
order and the physical repetition versus region-grid resize examples.

unlit defaults true. With unlit=false the existing lights, ambient and shadow
receiver shader apply; lit decals contribute receiver bounds/light relevance even
if the parent does not receive shadows. Decals do not cast separate shadows.
onTop, visible, maxDistance, zIndex, doubleSided and local transforms follow the
same plane policy. No widget tree is created; use SurfaceUI for buttons. UV tiles
use shader repetition without mutating a shared image's wrap state. Coplanar
separation is bounded; extreme zIndex does not move an image far from its face.

The SurfaceUI + Decal gallery demonstrates six faces, Attachment3D, normal/onTop
panels, rounded gradients/strokes, floor litter and tinted rotated tiled images.
The included transparent litter illustration is generated for this project.
