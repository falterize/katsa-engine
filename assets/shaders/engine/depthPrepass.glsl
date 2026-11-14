#pragma language glsl3
// Depth-only prepass for opaque meshes. User shaders never reach it: objects with a custom
// material are not eligible (see graphics/materials/opaqueMesh.lua).
#ifdef STAGE_VERTEX
#include "./chunks/mesh.glsl"
uniform highp mat4 viewProjection;

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    highp vec4 localPosition = vertexPosition;
    if (skinEnabled) {
        localPosition = meshSkinMatrix() * localPosition;
    }
    return viewProjection * meshModelMatrix() * localPosition;
}
#endif

#ifdef STAGE_PIXEL
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    return vec4(1.0);
}
#endif
