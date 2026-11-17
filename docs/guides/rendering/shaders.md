# Shaders

Katsa shaders follow Godot 4's model: a shader file declares a `shader_type`, optional
`render_mode`s, `uniform`s and the entry functions of that type (`vertex()`, `fragment()`,
`light()`). The files are GLSL; the engine wraps them in a template program, so a few lines
can change how a mesh is displaced, coloured or lit while skinning, instancing, shadows,
fog and tone mapping keep working.

Shader files are used by two nodes:

| Node | `shader_type` | Runs on |
| --- | --- | --- |
| `Shader3D` | `spatial` | 3D meshes, decals, particles, beams and trails in its subtree |
| `Shader2D` | `canvas_item` | the interface pixels (and optionally the 3D render) inside its rectangle |

`sky` and `fog` shader types do not exist yet.

## A first shader

```glsl
shader_type spatial;

uniform float amplitude : hint_range(0.0, 1.0) = 0.1;
uniform vec3 glow : source_color = vec3(1.0, 0.35, 0.08);

void vertex() {
    VERTEX.y += sin(TIME * 2.0 + VERTEX.x * 4.0) * amplitude;
}

void fragment() {
    ALBEDO = mix(ALBEDO, glow, 0.25 + 0.2 * sin(TIME * 2.0));
}
```

```lua
world:create('Shader3D', {
    shaderPath = 'scene://shaders/wave.glsl',
    animated = true,
    uniforms = { amplitude = 0.08 },
}, mesh)
```

Shader paths resolve like every asset path (`scene://`, `shared://`, project paths). Scenes keep
their shaders in `assets/shaders/`. Examples live in scenes: `shaderLab` (tint, wave, pixel UV,
PlayStation vertex snap, toon light, CRT static, mosaic), `platformer` (speed blur),
`stareShooter` (retro screen on F6, a `Datamosh` screen shader on F7 (off until switched on; F8 pins the frame on screen so only motion tears it), plus a disabled `VertexSnap` node under World3D to switch on in the Workspace). Open them as code to copy from.

## File structure

```glsl
shader_type spatial;                    // required, first statement
render_mode unshaded, cull_disabled;    // optional, comma separated

#include "./common.glsl"               // splice another file, relative or project path

uniform float strength : hint_range(0.0, 2.0) = 1.0;   // declaration, hint, default
varying vec2 affineUV;                  // vertex -> fragment

float helper(float x) { return x * strength; }          // any GLSL functions and structs

void vertex() { ... }
void fragment() { ... }
void light() { ... }
```

Everything outside the entry functions is ordinary GLSL (`const`, `struct`, functions,
`#define`). Preprocessor lines (`#define`, `#ifdef`) work. The entry functions have no
parameters: the built-in variables below are in scope.

### Uniforms

`uniform <type> name [: hint[(args)]] [= default];`

* Defaults are literals or constructors of literals: `1.0`, `true`, `vec3(0.2, 0.4, 0.6)`.
  They are applied when the node does not set the uniform, so a shader works without any Lua.
* Hints are metadata; they never reach the GPU compiler. The Inspector's uniform editor uses them:
  `hint_range(min, max[, step])` limits numbers, `source_color` marks a colour (channels 0..1 with a
  swatch), `hint_enum("A", "B")` offers an int by name. `hint_screen_texture` and
  `hint_depth_texture` and `hint_velocity_texture` are described under spatial.
* A `Shader3D`/`Shader2D` node sets values through `uniforms = { name = value }`. A name the file
  does not declare is an error, not a silent no-op. A value may be a number, boolean, a vector table
  or a managed value (animated values are read every frame).
* `sampler2D` uniforms take a texture path or manifest name (`uniforms = { tex = 'shared://textures/surfaces/stone.png' }`),
  a node that offers `getTexture()` (a `ViewportFrame` gives the 3D render it draws, so a mesh can show
  another world) or a texture object. `filter_nearest` / `filter_linear` after the colon choose the
  sampler filter for path values; `repeat_enable` (default) and `repeat_disable` choose wrapping (`repeat_disable` clamps to the edge pixel). Nothing is sent while a node has no texture yet.
* Several nodes may use the same file: every use gets its own uniforms and helper functions, so
  stacked shaders never collide on names.
* GLSL ES forbids uniform initializers; Katsa removes `= default` from the compiled text on every target.

### Includes

`#include "./file.glsl"` (relative to the including file) or `#include "scene://shaders/x.glsl"`
(project path). Includes nest, cycles are rejected, and compile errors point at the file and line
that was written, not at the composed text.

### Render modes

`spatial`: `unshaded` (no lighting, no light loop), `cull_disabled`, `cull_front`, `cull_back`,
`blend_mix` (default), `blend_add`, `blend_mul`, `depth_draw_never`, `shadows_disabled`.
Blend modes draw the object with the transparent pass; `depth_draw_never` skips depth writes.

`canvas_item`: `blend_mix`, `blend_add`, `blend_mul` (accepted; a Shader2D always mixes its result with
the original through `shaderTransparency`).

## spatial

The spatial program is the same one that draws every mesh. A user shader replaces nothing: the
engine does the surface maps, normal mapping, lighting, shadows, fog and tone mapping around your code.

```
vertex()  -> (rasterise) -> fragment() -> per light: light() -> fog / tone mapping
```

### vertex()

Runs after skinning and before the model matrix, so `VERTEX` is mesh-local like in Godot.

| Built-in | Type | Access | Meaning |
| --- | --- | --- | --- |
| `VERTEX` | `vec3` | inout | local position |
| `NORMAL` | `vec3` | inout | local normal |
| `UV` | `vec2` | inout | texture coordinate (before the image UV transform) |
| `COLOR` | `vec4` | inout | vertex colour |
| `MODEL_MATRIX` | `mat4` | in | local to world |
| `VIEW_MATRIX` | `mat4` | in | world to view |
| `PROJECTION_MATRIX` | `mat4` | in | view to clip |
| `MODELVIEW_MATRIX` | `mat4` | in | `VIEW_MATRIX * MODEL_MATRIX` |
| `TIME` | `float` | in | seconds of the world clock |
| `VIEWPORT_SIZE` | `vec2` | in | render size in pixels |
| `CAMERA_POSITION` | `vec3` | in | world position of the camera |
| `POSITION` | `vec4` | out | clip-space position; write it to replace the projection |

If the shader never mentions `POSITION`, the engine projects the (modified) vertex as usual. If it
does, `POSITION` is the final clip position, as in Godot.

### fragment()

Runs after texturing, tint, alpha test and the surface maps, before lighting.

| Built-in | Type | Access | Meaning |
| --- | --- | --- | --- |
| `FRAGCOORD` | `vec4` | in | `gl_FragCoord` |
| `SCREEN_UV` | `vec2` | in | fragment position over the viewport (0..1) |
| `UV` | `vec2` | in | texture coordinate after the image/decal transform |
| `UV_SCALE`, `UV_OFFSET` | `vec2` | in | the image UV transform: fragment `UV` is the vertex-stage (raw) UV times `UV_SCALE` plus `UV_OFFSET`. Use it when you interpolate UVs yourself in `vertex()` (a tiled floor otherwise loses its tiling) |
| `COLOR` | `vec4` | in | interpolated vertex colour |
| `WORLD_POSITION` | `vec3` | in | world position |
| `VIEW` | `vec3` | in | unit vector from the surface to the camera |
| `FRONT_FACING` | `bool` | in | false on the back of a triangle |
| `TIME` | `float` | in | world clock |
| `MODULATE` | `vec4` | in | the node tint and opacity |
| `TEXTURE` | `sampler2D` | in | the mesh image |
| `ALBEDO` | `vec3` | inout | base colour (already multiplied by tint and colour) |
| `ALPHA` | `float` | inout | opacity; at or below `alphaCutoff` the pixel is discarded |
| `NORMAL` | `vec3` | inout | world normal (after the normal map) |
| `ROUGHNESS` | `float` | inout | 0.04 to 1 |
| `METALLIC` | `float` | inout | 0 to 1 |
| `EMISSION` | `vec3` | inout | light added after lighting |
| `AO` | `float` | inout | ambient occlusion multiplier |

Writing `ALPHA` (or calling `discard`) keeps the alpha test active for otherwise opaque meshes.
Writing `ROUGHNESS`, `METALLIC`, `AO` or `EMISSION` turns on the physically based highlight for meshes
that have no surface appearance.

### light()

When a shader defines `light()` it runs once per light, replacing the default Lambert + GGX
shading. Shadow, spot cone and distance falloff are already in `ATTENUATION`.

| Built-in | Type | Access | Meaning |
| --- | --- | --- | --- |
| `NORMAL` | `vec3` | in | surface normal |
| `VIEW` | `vec3` | in | toward the camera |
| `LIGHT` | `vec3` | in | toward the light |
| `LIGHT_COLOR` | `vec3` | in | light colour times intensity |
| `ATTENUATION` | `float` | in | cone * falloff * shadow visibility |
| `ALBEDO` | `vec3` | in | final albedo |
| `ROUGHNESS`, `METALLIC` | `float` | in | final material values |
| `TIME` | `float` | in | world clock |
| `DIFFUSE_LIGHT` | `vec3` | inout | add diffuse light; it is multiplied by `ALBEDO` afterwards |
| `SPECULAR_LIGHT` | `vec3` | inout | add specular light |

The GGX helpers `materialSpecular(normal, direction, view, f0, roughness)` and
`materialSpecularTerms` are available inside `light()`. `unshaded` skips `light()`.

### Varyings

`varying` carries data from `vertex()` to `fragment()`. The PlayStation vertex-snap shader in `shaderLab`
uses two of them to get affine texture mapping: `uv * w` and `w` interpolate perspective-correctly,
and their quotient in `fragment()` is the screen-linear interpolation of `uv`.

```glsl
shader_type spatial;
uniform float snapScale : hint_range(10.0, 400.0) = 75.0;
varying vec2 affineUV;
varying float affineW;

void vertex() {
    vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    vec2 snapped = floor(snapScale * clip.xy / clip.w) / snapScale;
    POSITION = vec4(snapped * clip.w, clip.z, clip.w);
    affineUV = UV * clip.w;
    affineW = clip.w;
}

void fragment() {
    ALBEDO = texture(TEXTURE, affineUV / affineW).rgb * MODULATE.rgb * COLOR.rgb;
}
```

### Shadows

The shadow depth pass runs the user `vertex()` too, so displaced geometry casts the shadow it shows.
In that pass `VIEW_MATRIX` and `PROJECTION_MATRIX` are identity and `POSITION` is ignored, because the
light's projection is applied afterwards: displace through `VERTEX`, not through `POSITION`.
The standard texture alpha stays the shadow alpha source; `fragment()` alpha changes are not reproduced.
`shadows_disabled` removes the object from shadow casting.

### Particles, beams and trails

Particle shaders use the same file type. Vertices arrive in world space, so `MODEL_MATRIX` is the
identity and `VERTEX` is the world position of the quad corner. Sprites are lit by the simple particle
model after `fragment()` (`ALBEDO`, `ALPHA`, `EMISSION` apply); `light()` is not used for them.

### Stacking and bounds

Several Shader3D nodes may apply to one object (shader layers decide which); their `vertex()`,
`fragment()` and `light()` functions run in order. Set `animated = true` for time-dependent shaders.
A vertex shader changes the object's extent: choose `boundsMode = 'Padding'` with a world-unit
`shadowBoundsPadding` to keep tight culling, or the default `Conservative`.

### Scene textures

```glsl
uniform sampler2D screen_tex : hint_screen_texture;  // the opaque scene colour
uniform sampler2D depth_tex  : hint_depth_texture;   // the opaque scene depth
void fragment() { ALBEDO = texture(screen_tex, SCREEN_UV).rgb; }
```

`uniform sampler2D motion : hint_velocity_texture;` gives the per-pixel motion of the opaque scene (read it with
`SCREEN_UV`): `rg` is the current uv minus last frame's uv of the same surface point, `b` is 1 where a moving
mesh wrote it. A glass or water mesh can smear what is behind it only along real motion:
`texture(screen_tex, SCREEN_UV - texture(motion, SCREEN_UV).rg * 6.0)`. The pass runs only when a material asks
for it; the mesh itself (transparent) is not part of the velocity.

`linear_depth(float raw)` turns a depth sample into view distance along the camera axis
(`linear_depth(texture(depth_tex, SCREEN_UV).r)`); it works for perspective and orthographic cameras.
Do not declare a function of that name in your own shader.

`SCREEN_UV` is the fragment position over the viewport (0..1, top left origin). A material that
declares one of these samplers is drawn in the transparent pass, after the opaque scene, and the
engine binds the textures itself (the copy is made on first use each frame, so scenes without such
a shader pay nothing). The sampler never appears in `uniforms`.

## sky

`shader_type sky;` has only `fragment()` and replaces the world background. Put the file on a
`Shader3D` node of the world: the first enabled sky shader draws instead of the sky image (which
stays available as `SKY_COLOR`).

| Built-in | Type | Access | Meaning |
| --- | --- | --- | --- |
| `EYEDIR` | `vec3` | in | unit direction of the pixel's view ray |
| `SCREEN_UV` | `vec2` | in | position over the viewport |
| `TIME` | `float` | in | seconds |
| `POSITION` | `vec3` | in | camera position |
| `SKY_COLOR` | `vec3` | in | the configured sky image and tint |
| `COLOR` | `vec3` | inout | the pixel colour |

```glsl
shader_type sky;
uniform vec3 horizon : source_color = vec3(1.0, 0.5, 0.25);
void fragment() {
    COLOR = mix(horizon, SKY_COLOR, smoothstep(0.0, 0.4, clamp(EYEDIR.y, 0.0, 1.0)));
}
```

## fog

`shader_type fog;` has only `fragment()` and runs for every sample of the volumetric fog ray march
(enable `Environment.fog.volumetric`). The first enabled fog shader on a `Shader3D` node is used.

| Built-in | Type | Access | Meaning |
| --- | --- | --- | --- |
| `WORLD_POSITION` | `vec3` | in | the sample position |
| `CAMERA_POSITION`, `EYEDIR` | `vec3` | in | the ray origin and direction |
| `DISTANCE` | `float` | in | distance along the ray |
| `TIME` | `float` | in | seconds |
| `DENSITY` | `float` | inout | fog density at the sample (starts at the Environment value) |
| `ALBEDO` | `vec3` | inout | fog colour |
| `EMISSION` | `vec3` | inout | light the fog gives off |

Mesh pipelines ignore sky and fog files; a sky file cannot be used as a mesh shader.

## canvas_item

`shader_type canvas_item` shaders run on a Shader2D region.

| Built-in | Type | Access | Meaning |
| --- | --- | --- | --- |
| `COLOR` | `vec4` | inout | starts as texel times vertex colour; write the result |
| `UV` | `vec2` | in | texture coordinate on the whole source canvas |
| `REGION_UV` | `vec2` | in | 0..1 inside the node's rectangle |
| `REGION_ORIGIN`, `REGION_SIZE` | `vec2` | in | the rectangle in source pixels |
| `CANVAS_SIZE` | `vec2` | in | source canvas size in pixels |
| `SCREEN_PIXEL` | `vec2` | in | physical pixel position |
| `VERTEX_COLOR` | `vec4` | in | the draw colour |
| `FRAGCOORD` | `vec4` | in | `gl_FragCoord` |
| `TIME` | `float` | in | UI clock |
| `TEXTURE` | `sampler2D` | in | the snapshot being processed |

`uniform sampler2D name : hint_screen_texture;` gives the same snapshot as `TEXTURE` under your own
name (sample it with `UV`). `hint_depth_texture` gives the opaque depth of the 3D render under the
interface (read it with `linear_depth(texture(d, UV).r)`); it needs a Shader2D layer that interacts with
`Default3D`, otherwise the depth reads as far away (1.0).

### Seeing only some 3D layers (`viewLayers`)

`hint_screen_texture` shows the whole 3D render. To see only some of it, give the Shader2D a
`viewLayers` list (a comma separated string, or a table from code) of layer group names and read the
result with two more hints:

```lua
world.layerGroups:add('Enemies')
for _, enemy in ipairs(enemies) do
    enemy.layerGroup = 'Enemies' -- every Node3D carries a layerGroup
end
ui:create('Shader2D', {
    shaderPath = 'scene://shaders/outline.glsl',
    viewLayers = 'Enemies',
})
```

```glsl
uniform sampler2D layer : hint_layer_texture;       // colour of only those groups, alpha 0 elsewhere
uniform sampler2D layer_depth : hint_layer_depth_texture; // their opaque depth
```

This is Godot's recipe of a camera with a `cull_mask` in a SubViewport: the engine renders the 3D scene
a second time with the main camera narrowed to those groups. The pass runs at half the main
`renderDensity` (at least 0.5), draws no sky, gizmos, post effects, interface, transparent objects or particles (those stay in the main pass), and reads the main
shadow atlas. Shaders with the same groups share one pass; a pass is made once a frame and only when a
shader declares one of the two hints and names groups. It still pays for a second scene submission, so
watch the number of different group sets. Like the other scene hints it needs a Shader2D layer that
interacts with `Default3D`; otherwise both textures are empty (transparent, far). The stareShooter
scene shows it: F9 outlines the character (`assets/shaders/outline.glsl`).

Two more opt-in hints make temporal effects possible (neither costs anything unless a shader declares it):

- `uniform sampler2D previous : hint_history_texture;` is this shader's own result from the previous frame
  (the first frame sees the unprocessed picture). Sample it with `UV`; feeding it back gives trails,
  smoothing or datamosh.
- `uniform sampler2D motion : hint_velocity_texture;` is the per-pixel motion of the 3D render: `rg` is the
  current uv minus the uv the same surface point had last frame, so `texture(history, UV - motion.rg)`
  fetches where a pixel came from; `b` is 1 where a moving mesh wrote the value (0 for camera motion only).
  Like depth it needs a layer that interacts with `Default3D`; otherwise it is zero. Skinned meshes use
  their previous bone palette. Not covered: vertices a user shader displaces, blend shapes, particles and
  transparent meshes.

`stareShooter`'s `Datamosh` (F7) uses both.

`vertex()` receives `VERTEX` (screen pixels), `UV`, `COLOR`, `CANVAS_VERTEX`, `TIME`. `shaderTransparency` mixes
the result with the untouched pixel after `fragment()`.

```glsl
shader_type canvas_item;
uniform float pixelSize : hint_range(1.0, 64.0) = 8.0;

void fragment() {
    float block = max(1.0, pixelSize);
    vec2 localPixel = UV * CANVAS_SIZE - REGION_ORIGIN;
    vec2 center = (floor(localPixel / block) + 0.5) * block;
    center = clamp(center, vec2(0.5), max(vec2(0.5), REGION_SIZE - vec2(0.5)));
    COLOR = texture(TEXTURE, (REGION_ORIGIN + center) / CANVAS_SIZE) * VERTEX_COLOR;
}
```

## Shader layers

```lua
world.shaderLayers:add('Static', 10)
world.shaderLayers:add('Pixel', 20)
world.shaderLayers:setInteracts('Pixel', 'Default3D', false)
```

Shader layers work like layer groups: one symmetric interaction matrix. Every world starts with
`Default2D` (Shader2D nodes) and `Default3D` (Shader3D nodes and the 3D render); they do not interact
at first. New layers interact with every existing layer. Priority (Default layers 0, custom positive)
orders effects. Two enabled effects whose layers do not interact cannot combine on the same object or
region: the higher-priority one wins and the lower one is suppressed until it is disabled.
The Workspace's Shaders button opens the matrix editor (add, rename, delete, priority, table or list).
A `Shader2D` also sees the 3D render under it (background, `hint_screen_texture`, `hint_depth_texture`) when its layer
interacts with `Default3D` or with the layer of an enabled `Shader3D`; it always gets the whole 3D render, not only the
parts a particular layer affects.
Camera/object visibility and physics collision groups remain separate systems.

## Shader2D

```lua
local tv = ui:create('Shader2D', {
    position = { 0, 300, 0, 100 },
    size = { 0, 400, 0, 250 },
    zIndex = 10,
    shaderLayer = 'Static',
    shaderPath = 'scene://shaders/tvStatic.glsl',
    backgroundTransparency = 1,
    shaderTransparency = 0.25,
    uniforms = { noiseStrength = 0.2 },
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

### Scope: 2D by default, 3D on request

A Shader2D processes interface pixels only, unless its layer interacts with `Default3D`. Then the 3D
render underneath (the world behind the UI, or the UI background of a ViewportFrame owner) is part of
the snapshot the effect reads, and the processed result replaces the region, 3D pixels included.
Give full-screen filters over the game view (the Stare Shooter retro screen, the platformer speed
blur) their own layer, e.g. `Screen`, which interacts with Default3D by default, or turn on the
`Default2D`/`Default3D` checkbox to let every Default2D effect process 3D. The old per-node
`affects3D` property is gone.

BackgroundTransparency controls only the background. ShaderTransparency=0 applies
the effect fully; 1 bypasses it. Intermediate values mix original and processed
premultiplied RGBA. Enabled=false bypasses the effect and retains Frame visibility
semantics. ViewportFrame rendering is processed as image content, with its inner UI.
Two owner-level canvases are reused. No synchronous framebuffer readback is used.
Nested rounded clipping remains stencil-based; suppression uses rectangular exclusion.

## Shader3D scope

Shader3D belongs to World3D space only: creating it under a UI node, ScreenUI or World2D is rejected
("use Shader2D in interface hierarchies"), and it must have a World3D ancestor. Shader3D is an
organizational Folder plus a material modifier. `world:create` without an explicit parent places it
directly beneath World3D. As a direct child of World3D it affects that world's 3D renderables. Inside a
Folder/Mesh it affects that parent's subtree, including its own descendants. It never reaches World2D,
Billboard/SurfaceUI content or an independent viewport world. Scope follows live parenting. Meshes,
decals and particle geometry use the same resolver.

```lua
local group = world:create('Folder', { name = 'EffectGroup' })
world:create('Shader3D', {
    shaderPath = 'scene://shaders/wave3D.glsl',
    shaderLayer = 'Static',
    animated = true,
    uniforms = { waveAmplitude = 0.1, glowColor = { 0.1, 0.7, 1 } },
}, group)
world:create('Mesh3D', { texture = 'bricks' }, group)
```

Environment.systemLayers maps lighting, shadows, fog and toneMapping to
named layers (initially Default). Active higher Shader3D layers may suppress their
sampling/evaluation on affected meshes. This does not reorder shadow-map generation,
depth passes or opaque/transparency dependencies. Maps can still serve other objects.
Cached stacks are released with their world resource scope.

## Shader tags

Tag a `Shader3D` or `Shader2D` with `#shader-<group>` and it acts only on the nodes that carry
the same tag **and on their descendants**, wherever they are in the tree. `#noshader-<group>` on a
node switches the group off for that node and its subtree.

```lua
local glow = scene.world:create('Shader3D', { shaderPath = 'shared://shaders/glow.glsl' })
glow:addTag('#shader-glow')
model:addTag('#shader-glow')                  -- the whole model glows
eyes:addTag('#noshader-glow')                 -- ... except the eyes and what is inside them
model:setAttribute('shaderDepth.glow', 2)     -- only two levels below the model
model:removeTag('#shader-glow')               -- unbinds it again
```

**Levels.** Reach is counted in tree levels, the tagged node being level 0. How far an include tag
reaches is the node's attribute `shaderDepth.<group>`, else the whole subtree. How far an exclusion reaches is the node's attribute
`noShaderDepth.<group>`, else the whole subtree. `-1` (or no value) always means unlimited.

**Which tag decides.** For an object, the nearest ancestor (the object itself counts) whose tag
*reaches* it decides. On one node an exclusion beats an inclusion.

| Tags on node `R` | Level 0 | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- | --- |
| `#shader-fx` | yes | yes | yes | yes | yes |
| `#shader-fx`, `shaderDepth.fx = 1` | yes | yes | no | no | no |
| `#shader-fx` + `#noshader-fx` (no depths) | no | no | no | no | no |
| `#shader-fx` depth 3 + `#noshader-fx` depth 1 | no | no | yes | yes | no |

An `#shader-` tag below an exclusion switches the group back on for its own subtree.

- Shaders of one group stack by their layer priority; shader layers and the interaction matrix
  apply as usual, in 2D and 3D.
- A shader without a `#shader-` tag keeps the subtree scope.
- A shader binds only nodes of its own world kind; 2D and 3D groups never mix.
- Environment, sky and fog shaders are not tag-bound.
- 2D: a post effect filters the rectangle of the outermost reached `UINode`, so its children are
  inside it and depth cannot separate them; `#noshader-` cuts the excluded node's rectangle out.
- The inspector edits the tags in the ordinary `tags` row (a `#` tag must look like
  `#shader-<group>` or `#noshader-<group>`), the depth attributes under Attributes.
- A depth attribute without a matching tag does nothing.

## Errors

<details><summary>Error messages and how they are reported</summary><br>

A shader that fails to parse or compile raises an error that names the file and line you wrote:

```
scene://shaders/wave.glsl:7: 'ALBEDOO' : undeclared identifier
```

Unknown `shader_type`, unsupported `render_mode`, entry functions the type does not have, and
uniforms set by a node but not declared by the file are errors as well.

</details>

## How the engine builds programs

<details><summary>Program building, caching and the include system</summary><br>

This section is for engine work; shader authors can stop here.

```
source/engine/graphics/shaders/
    composer/      tokens.lua parser.lua builtins.lua source.lua init.lua
    programs.lua   compile(template, options) -> native shader + program metadata
assets/shaders/engine/
    world.glsl     spatial template (vertex, fragment, light)
    shadow.glsl depthPrepass.glsl wireframe.glsl sky.glsl surfaceBlend.glsl ...
    canvas/item.glsl      canvas_item template
    chunks/        mesh (skin, instancing), pbr, surface (maps), lighting (light loop),
                   shadowSampling, fog, depth (post depth helpers)
    post/          full-screen passes (glow, ssao, dof, fxaa, volumetric fog, finish ...)
    particles/     sprite.glsl (particle, beam, trail template), sprite2d.glsl
```

* **Templates** are dialect GLSL (`vec4 position(...)`, `vec4 effect(...)`, `attribute`, `varying`,
  `extern`, `#ifdef STAGE_VERTEX` / `STAGE_PIXEL`), translated for GLSL 330 core and GLSL ES 300 by
  `source/katsa/graphics/shaderTranslator.lua`.
* **Composer directives** in templates: `#include "path"`, `#specialize <type> <name>` (a `uniform` in the
  general program, a `const` when `options.constants` has a value: this is how variants drop unused
  branches and uniforms), and `#user_code` (the user shaders' uniforms, helpers and wrapped entry points).
* **Flags** are `#define`s from `options.defines` (`KATSA_SOLID`, `KATSA_EARLY_DEPTH`, `KATSA_LIGHT_MASK`,
  `KATSA_NO_DIRECTIONAL`, `KATSA_SHADOW_STANDARD`, `KATSA_SHADOW_SAMPLES`) plus flags the composer derives
  from the user shaders (`KATSA_USER_VERTEX/FRAGMENT/LIGHT`, `KATSA_USER_POSITION`, `KATSA_USER_ALPHA`,
  `KATSA_USER_PBR`, `KATSA_USER_UNSHADED`). Templates use them with `#ifdef`.
* **Entry functions** become real GLSL functions whose parameters are the built-in variables
  (`builtins.lua` is the contract; keep this guide in step with it). The template declares locals with those
  names and calls the wrapper macro, e.g. `KATSA_USER_FRAGMENT;`.
* **User identifiers** are prefixed `s<index>_` per shader instance. Uniform metadata (defaults, hints) stay in
  Lua; `program.uniforms[compiled] = { shader, name }` maps compiled names back to node uniforms.
* **Variants**: `pipeline/shaderVariants.lua` selects constants and flags per draw; `materials/material.lua`
  builds the main and shadow programs of a user shader stack.
* Adding a built-in: edit `builtins.lua`, declare the local in each template that runs that entry point,
  document it above, and add a case to `validation/tests/versions/v108_8/shaderPrograms.lua`.
* `validation/tests/katsa/shaderCompile.lua` compiles every engine shader in several variants, and every
  user shader found under `game` and the test fixtures with each template of its type, on desktop and ES.

</details>
