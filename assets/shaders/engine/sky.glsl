#pragma language glsl3
// Sky background drawn as a full-screen quad before the world. The ray maths is shared with the
// user sky shader (skyShader.glsl) through chunks/skyCoords.glsl.
#ifdef STAGE_PIXEL
#include "./chunks/skyCoords.glsl"

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    return vec4(skyColor(image, skyRay(uv)), 1.);
}
#endif
