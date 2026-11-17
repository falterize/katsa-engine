// Velocity caused by the camera alone: every pixel's surface point is rebuilt from the scene depth
// and projected with last frame's camera. The result is current uv minus previous uv. Moving meshes
// are drawn over this by velocity.glsl.
#include "../chunks/depth.glsl"
uniform highp mat4 reprojection;      // previous view-projection * inverse(current view)
uniform highp vec2 projectionScale;   // the x and y scale of the camera projection

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    highp float z = viewDepth(uv);
    highp vec2 ndc = uv * 2.0 - 1.0;
    highp float w = orthographic ? 1.0 : z;
    highp vec4 view = vec4(ndc.x * w / projectionScale.x, ndc.y * w / projectionScale.y, z, 1.0);
    highp vec4 before = reprojection * view;
    if (before.w < 0.00001) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }
    highp vec2 previous = (before.xy / before.w) * 0.5 + 0.5;
    return vec4(uv - previous, 0.0, 1.0);
}
