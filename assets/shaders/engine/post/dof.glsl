// Depth of field (Godot's far/near blur): the circle of confusion follows the distance from the
// camera; taps closer than the centre pixel's own blur are weighted down so a sharp foreground
// never bleeds into a blurred background.
#include "../chunks/depth.glsl"
uniform highp vec2 texel;      // one pixel of the image in uv units
uniform highp float maxRadius; // blur radius in pixels
uniform bool farEnabled;
uniform highp vec2 farRange;   // distance, transition
uniform bool nearEnabled;
uniform highp vec2 nearRange;
uniform int sampleCount;

// 0 sharp .. 1 fully blurred; the sky counts as infinitely far.
highp float confusion(highp vec2 uv) {
    highp float z = isSkyDepth(uv) ? 1e6 : viewDepth(uv);
    highp float coc = 0.0;
    if (farEnabled) {
        coc = max(coc, clamp((z - farRange.x) / farRange.y, 0.0, 1.0));
    }
    if (nearEnabled) {
        coc = max(coc, clamp((nearRange.x - z) / nearRange.y, 0.0, 1.0));
    }
    return coc;
}

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    vec4 center = Texel(image, uv);
    highp float radius = confusion(uv) * maxRadius;
    if (radius < .5) {
        return center;
    }
    highp vec3 sum = center.rgb;
    highp float weights = 1.0;
    for (int i = 0; i < 32; i++) {
        if (i >= sampleCount) {
            break;
        }
        // A golden-angle spiral covers the disc evenly with few taps.
        highp float f = (float(i) + .5) / float(sampleCount);
        highp float a = float(i) * 2.3999632;
        highp vec2 offset = vec2(cos(a), sin(a)) * sqrt(f) * radius;
        highp vec2 at = uv + offset * texel;
        highp float reach = confusion(at) * maxRadius;
        highp float w = clamp(reach / max(length(offset), 1.0), 0.0, 1.0);
        sum += Texel(image, at).rgb * w;
        weights += w;
    }
    return vec4(sum / weights, center.a);
}
