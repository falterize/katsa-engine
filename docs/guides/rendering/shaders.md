# Shader2D, Shader3D and layers

```lua
world.shaderLayers:add('Static', 10)
world.shaderLayers:add('Pixel', 20)
world.shaderLayers:setSuppressed('Pixel', 'Default', true)
```

Default has priority 0; custom priorities are positive. A higher enabled effect
suppresses selected lower layers within its own scope/rectangle. Disabling the
upper effect restores lower effects. Suppression is directed, not a collision matrix.
Workspace's Shaders button creates layers, edits priority and toggles suppression.
Camera/object visibility and physics collision groups remain separate systems.

## Shader2D

```lua
local tv = ui:create('Shader2D', {
    position = { 0, 300, 0, 100 },
    size = { 0, 400, 0, 250 },
    zIndex = 10,
    shaderLayer = 'Static',
    shaderPath = 'assets/shaders/examples/tvStatic.glsl',
    backgroundTransparency = 1,
    shaderTransparency = 0.25,
}, ui.content)
local preview = ui:create('ViewportFrame', { size = { 1, 0, 1, 0 } }, tv)
```

The Frame background and its descendants draw normally, then its effect processes
only its rectangle from a snapshot of lower content. Later/higher screen UI stays
unaffected. ZIndex establishes screen composition order; shaderLayer priority and
order break ties between Shader2D siblings at equal ZIndex. Existing CanvasGroup
hierarchy/opacity/clipping are retained rather than flattened globally. Put effects
that must be ordered solely by shader layers at the same ZIndex and UI parent.
Descendants are included regardless of their local child ordering.

BackgroundTransparency controls only the background. ShaderTransparency=0 applies
the effect fully; 1 bypasses it. Intermediate values mix original and processed
premultiplied RGBA. Enabled=false bypasses the effect and retains Frame visibility
semantics. ViewportFrame rendering is processed as image content, with its inner UI.

shaderPath uses a normal LÖVE `vec4 effect(vec4, Image, vec2, vec2)` program. Uniforms
in the node are forwarded when used. `time`/`materialTime` receive the UI/world clock.
The input image UV addresses the full composition target; screen coordinates are
physical target pixels. Supply explicit resolution uniforms for pixel-sized effects.
Two owner-level canvases are reused. No synchronous framebuffer readback is used.
Nested rounded clipping remains stencil-based; suppression uses rectangular exclusion.

## Shader3D

Shader3D is an organizational Folder plus a material modifier. world:create without
an explicit parent places it directly beneath World3D. As a direct child
of World3D it affects that world's 3D renderables. Inside a Folder/Mesh it affects
that parent's subtree, including its own descendants. It never reaches World2D,
Billboard/SurfaceUI content or an independent viewport world. Scope follows live
parenting. Meshes, decals and particle geometry use the same resolver.

```lua
local group = world:create('Folder', { name = 'EffectGroup' })
world:create('Shader3D', {
    shaderPath = 'assets/shaders/examples/wave3D.glsl',
    shaderLayer = 'Static',
    animated = true,
    uniforms = { waveAmplitude = 0.1, glowColor = { 0.1, 0.7, 1 } },
}, group)
world:create('Mesh3D', { texture = 'bricks' }, group)
```

Shader3D files contain optional tagged GLSL sections:
`// @vertexDeclarations`, `// @vertexCode`, `// @fragmentDeclarations`,
`// @fragmentCode`. Vertex code changes `localPosition`; fragment code changes
RGB `result`. Built-in materialTime is supplied. Uniform names are namespaced per
stack entry so two instances can use the same shader path with independent values.
Other shared helper/type declarations should have unique names. Arbitrary complete
replacement shader programs are not the Shader3D contract. Use the examples as code.
Particle vertex positions are world-space quad positions, unlike mesh-local positions.
Particles remain unlit and do not gain shadow casting through Shader3D.

Mesh vertex hooks are shared by main and shadow shaders. Standard texture alpha
cutouts remain the shadow alpha source; arbitrary fragment-only alpha alterations
are not reproduced in the shadow pass. animated should be true for time-dependent
hooks. Fragment-only effects do not force geometry shadow updates. Conservative
vertex bounds avoid false culling; choose boundsMode=Padding and provide a correct
world-unit shadowBoundsPadding to retain tighter culling/update regions.

Environment.systemLayers maps lighting, shadows, fog and toneMapping to
named layers (initially Default). Active higher Shader3D layers may suppress their
sampling/evaluation on affected meshes. This does not reorder shadow-map generation,
depth passes or opaque/transparency dependencies. Maps can still serve other objects.
Cached stacks are released with their world resource scope. Runtime hot editing many
unique paths/stacks retains cache entries until scope release; it is not a live shader
source editor/reloader. Shader2D and Shader3D both respect their independent world.
