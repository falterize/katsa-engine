// Depth-aware blur of the occlusion target (run once per axis).
#include "../chunks/depth.glsl"
uniform highp vec2 direction; // one texel step along the blur axis

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    highp float centerZ = viewDepth(uv);
    highp float sum = Texel(image, uv).r, weights = 1.0;
    for (int i = 1; i <= 3; i++) {
        for (int s = -1; s <= 1; s += 2) {
            highp vec2 at = uv + direction * float(i * s);
            // Taps across a depth edge would smear occlusion over the wrong surface.
            highp float w = 1.0
                - smoothstep(0.0, .05 * abs(centerZ) + .02, abs(viewDepth(at) - centerZ));
            w *= 1.0 - float(i) * .2;
            sum += Texel(image, at).r * w;
            weights += w;
        }
    }
    return vec4(vec3(sum / weights), 1.0);
}
