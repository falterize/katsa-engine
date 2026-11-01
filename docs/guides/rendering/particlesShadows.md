# v70 rendering, particles, UI and audio

## Particle budgets and shadows

rate is births per second; maxParticles is the emitter live-count cap. Shared
world.particles.maxParticles, collisionBudget and maxSteps independently bound total
live particles, raycasts per update and fixed-step catch-up. Quality is no longer a
runtime property. OffscreenBehavior Pause retains v69 visibility culling; Simulate
permits background simulation. A draw count of zero alone does not imply no simulation.

unlit=true bypasses light evaluation, so particles do not darken in shadows.
unlit=false enables approximate sprite lighting. receiveShadow=true additionally
samples enabled sun/local shadows. castShadow=true contributes alpha-tested sprite
quads to shadow maps. shadowGroup respects world group interaction rules.
shadowMaxParticles limits shadow geometry and shadowAlphaCutoff excludes faint pixels.
This is alpha-tested geometry, not volumetric transmission. Sprite lighting selects
up to eight local lights. Camera/Velocity/Axes orientation and lifetime size/rotation
are shared by visible sprites and shadow geometry. Offscreen shadow casters may still
need work because they can cast into a visible region. Disabling shadow participation
releases the proxy buffer; destruction releases all emitter buffers.

## Rendering cost

Wireframe uses a minimal dedicated vertex/edge shader, skips normal material
composition, light/shadow preparation, particle draws and screen postprocessing.
It supports skinned meshes; UI remains filled.

Opaque batches retain instancing. Per-object compact light palettes reject lights
whose spheres cannot overlap conservative object bounds; unknown custom shader bounds
retain all lights. This reduces fragment work without reducing configured light count.
Selected Shader3D nodes are collected once per render preparation. Transform input
validation only repeats when authored values change. Specular shading uses a
GGX/Schlick approximation; this does not add a full PBR/IBL pipeline.

ViewportFrame now restores ancestor stencil masks after canvas switches. This fixes
Pixel/CRT Shader2D effects in the suppression-layer scene. Shader ZIndex controls
application ordering; layer and suppression membership remain applicable.

## ScrollFrame

scrollBarThickness, scrollBarImageColor3, scrollBarImageTransparency,
verticalScrollBarPosition (Left/Right), topImage, midImage and bottomImage configure
its vertical scrollbar. PascalCase aliases match the equivalent property names.
Three images form the thumb caps and stretchable middle; missing images use a solid
fallback. The thumb is drawn after children. Horizontal scrolling is not added.

Clip=true crops descendant UI to the frame rectangle. Clip=false permits descendants
outside it, while ancestor clipping still applies. It does not change the scroll range.
The settings follow Roblox's ScrollingFrame customization conventions:
https://create.roblox.com/docs/ui/scrolling-frames

## Audio and inspector

Low-pass passes highgain only; high-pass passes lowgain only; band-pass supports both.
Native filter failures report the underlying reason. Filter support still depends on
the katsa/OpenAL backend. Numeric Debug labels initialize immediately and refresh while
visible. Selection updates Properties values. Particle budgets have a Workspace entry.

Maximum Graphics Laboratory requests high render density, MSAA, shadow resolution and
sampling, mapped materials, lit shadowed/colliding particles and fog. Renderer device,
pixel/memory and shadow-atlas limits remain enforced; requested maxima can be clamped.
Animation & Physics Laboratory and all earlier examples are available in menu categories.
