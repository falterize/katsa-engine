#pragma language glsl3
// canvas_item program: Shader2D post effects and UI materials.
//
// COLOR starts as the sampled texel times the vertex colour. A Shader2D reads the composited
// scene canvas: UV addresses the whole canvas, REGION_UV is 0..1 inside the node's rectangle,
// and `shaderAmount` (1 - shaderTransparency) blends the result with the untouched pixel.
uniform highp float time;
uniform highp vec2 canvasSize;
uniform highp vec2 regionOrigin;
uniform highp vec2 regionExtent;
uniform float shaderAmount;

#user_code

#ifdef STAGE_VERTEX
vec4 position(mat4 transformProjection, vec4 vertexPosition) {
#ifdef KATSA_USER_VERTEX
    highp vec2 VERTEX = vertexPosition.xy;
    vec2 UV = VaryingTexCoord.st;
    vec4 COLOR = VaryingColor;
    highp vec2 CANVAS_VERTEX = vertexPosition.xy;
    highp float TIME = time;
    KATSA_USER_VERTEX;
    vertexPosition.xy = VERTEX;
    VaryingTexCoord.st = UV;
    VaryingColor = COLOR;
#endif
    return transformProjection * vertexPosition;
}
#endif

#ifdef STAGE_PIXEL
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    vec4 base = Texel(image, uv) * color;
#ifdef KATSA_USER_FRAGMENT
    highp vec4 FRAGCOORD = gl_FragCoord;
    highp vec2 UV = uv;
    highp vec2 SCREEN_PIXEL = screenPosition;
    vec4 VERTEX_COLOR = color;
    highp float TIME = time;
    highp vec2 CANVAS_SIZE = max(canvasSize, vec2(1.0));
    highp vec2 REGION_ORIGIN = regionOrigin;
    highp vec2 REGION_SIZE = max(regionExtent, vec2(1.0));
    highp vec2 REGION_UV = (uv * CANVAS_SIZE - REGION_ORIGIN) / REGION_SIZE;
    vec4 COLOR = base;
#define TEXTURE image
    KATSA_USER_FRAGMENT;
#undef TEXTURE
    return mix(base, COLOR, shaderAmount);
#else
    return base;
#endif
}
#endif
