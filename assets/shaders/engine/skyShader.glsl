#pragma language glsl3
// Sky background with a user `shader_type sky` fragment(). Built-ins: EYEDIR (unit view ray),
// SCREEN_UV, TIME, POSITION (camera), SKY_COLOR (the configured sky image) and COLOR (output).
#ifdef STAGE_PIXEL
#include "./chunks/skyCoords.glsl"
uniform highp float time;
uniform highp vec3 cameraPosition;

#user_code

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    highp vec3 ray = skyRay(uv);
    vec3 SKY_COLOR = skyColor(image, ray);
    vec3 COLOR = SKY_COLOR;
#ifdef KATSA_USER_FRAGMENT
    highp vec3 EYEDIR = normalize(ray);
    vec2 SCREEN_UV = uv;
    highp float TIME = time;
    highp vec3 POSITION = cameraPosition;
    KATSA_USER_FRAGMENT;
#endif
    return vec4(COLOR, 1.);
}
#endif
