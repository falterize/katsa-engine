# Shared image component and viewport resolution

UI ImageLabel and image-bearing Button use imageMode and the shared component.

| Mode | Settings and units |
| --- | --- |
| Decal | One image; fitMode Fit/Crop/Stretch |
| Texture | Repetition size textureSize in logical pixels and textureOffset in pixels |
| Tiles | tileSize UDim2 relative to the destination area plus pixels; tileOffset in pixels |
| Atlas | atlasGrid columns/rows, zero-based atlasFrame, fitMode Fit/Crop/Stretch |
| XML | xml manifest path; optional image override, automatic grid/filter, editable zero-based atlasFrame |

Workspace conditionally shows the selected mode's settings. Hidden values remain
stored. FitMode no longer selects tiling in new UI code. Crop clips inside the image
area, including atlas subframes. Texture uses an absolute repeat size; Tiles can
scale its grid with the destination through UDim2. Atlas advances when scene code
or Tween changes atlasFrame; the existing particle atlas playback remains available.

Since v65, Pixelate=true selects nearest filtering; false (the default) selects
linear filtering. There is no Environment-wide filtering default. Images loaded
by path cache separate sampler variants; imported in-memory textures get an isolated
nearest Canvas copy. A node never changes a shared image's sampler. Meshes, decals,
particles, sky, world UI and viewport canvases use the same policy. Text/font raster
quality is not changed by the image flag. SurfaceAppearance3D image UV modes map to authored
UVs; Texture uses nominal X/Y Size world units and Tiles uses a 16 pixels/unit nominal
X/Y area. They are not an automatic per-face box/triplanar projection.

Decal3D retains separate Decal/Texture/Tiles modes, plus Atlas. Texture repetition
uses surface world units, not screen pixels; Tiles uses selected surface area and
canvasPixelsPerUnit. The existing imageOffset/imageRotation remain applicable.

ViewportFrame.canvasSize is UDim2 relative to resolved frame width/height:
`{1,0,1,0}` is native size; `{2,0,2,0}` doubles resolution;
`{0,1024,0,512}` requests a fixed target. Size still controls the displayed rectangle.
CanvasSize controls render/overlay pixels and hit-coordinate mapping. Positive finite
sizes are required. GPU texture and per-world pixel budgets may reduce the allocation.
Environment.render controls renderDensity/MSAA and memory/pixel limits.
Higher targets add memory and full render cost; they cannot guarantee mobile FPS.

World2D overlay pixel offsets are in target pixels, so increasing CanvasSize makes
fixed-pixel controls smaller on display. Use Scale for resolution-independent layout.
BillboardUI retains its documented Screen/World3D base-size conversion and CanvasSize.

## XML atlas images

XML contains metadata and animation clips; the sprite pixels stay in a separate PNG.
Use the project flipbook manifest schema documented in [Physics2D](../physics/physics2D.md).
This is not an importer for arbitrary XML formats from other engines or atlas tools.

```lua
local sprite = scene.ui:create('ImageLabel', {
    imageMode = 'XML',
    xml = 'scene://animations/player.xml',
    image = 'scene://textures/player-red.png', -- Optional alternate atlas with the same layout.
    atlasFrame = 5,
    size = { 0, 32, 0, 32 },
    backgroundTransparency = 1,
})
```

Workspace shows `xml` only in XML mode. The manifest's `image`, `columns`, `rows`
and `pixelate` configure the sampler and grid automatically. `atlasGrid` stays hidden
because the manifest owns it. `atlasFrame` remains editable, starting at zero.
Changing it does not reread XML or restart playback. The `image` path stays editable
in XML mode: loading a manifest automatically fills `image` from its image attribute.
Replace it to override the art, or clear it to fill the default PNG again.
Changing XML updates an automatically filled path and preserves manual overrides. Alternate sprite atlases must have the same layout and match
any declared frame dimensions. Changing only the image does not reparse XML or
restart animation. When leaving XML mode without an override, rendering keeps the
last resolved sprite instead of failing because the image property is empty.
SurfaceAppearance3D uses its existing `colorMap` property for the equivalent override.
Manifest and image paths accept scene:// and shared:// asset roots.

Rendering validates and binds a manifest once per node/path/resources combination.
Changing `xml` loads the new manifest; invalid metadata raises an explicit error.
XML mode alone does not start an animation. To animate, create a playback controller:

```lua
local Xml = require('source.engine.animation.formats.flipbookXml')
local playback = Xml.playback(scene.resources, sprite)
playback:play('Run')
-- Advance from a scene system with the appropriate World2D simulation delta.
playback:update(dt)
```

`playback:pause()` allows manual frame selection while retaining the clip state.
The convenience `Xml.load(resources, path, target)` sets XML mode/path and creates
playback. ImageLabel and image-bearing Button share this mode; SurfaceAppearance3D
uses the manifest image as its color map and the same grid for its UV modes.
Decal3D uses the same imageMode API; its legacy mode property remains synchronized.

## Missing assets

An absent/empty ImageLabel image, an explicitly empty image-bearing Button,
a missing path or an undecodable image displays an opaque black/purple checker.
Ordinary text-only buttons keep their normal appearance. Missing XML image files
use the complete checker and bypass frame-dimension validation of the substitute;
valid replacement images must still match the declared atlas layout. The image
loader caches diagnostic textures and uses nearest filtering for clear checks.
Decal3D accepts an empty image and uses the same fallback. Errors remain available
through the resource journal for missing/undecodable files.

SurfaceAppearance3D already handles missing texture paths, including model material
maps. A deliberately untextured mesh remains its authored solid color; empty
optional normal/roughness/etc. maps do not turn a material into an error texture.
Loading an absent model file through Models.load produces a shared cube asset with
checker material and independent instances instead of terminating the scene.
Invalid model syntax or unsupported formats still report import errors.

Decal3D, ParticleEmitter2D and ParticleEmitter3D also support all five image modes.
UV origin/extent, sampler selection and XML loading live in the shared image
component; particle age-based atlas/clip selection lives in particles/image.lua.
The particle image path remains `texture`; SurfaceAppearance3D uses `colorMap`;
UI and Decal3D use `image`. XML fills the corresponding path automatically when
empty. Missing or invalid XML and incompatible atlas dimensions produce a checker
and a resource-journal report instead of interrupting rendering.

Missing 3D material maps use an object-local diagnostic checker with twelve cells
across the largest rest-mesh dimension. It remains visible on small models, needs
no UVs and follows movement, scaling and skeletal deformation without sliding
through world-space cells. Valid material texture sizing is unchanged.
