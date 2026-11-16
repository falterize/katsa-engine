// Multiplies the occlusion into the image. The occlusion target is half resolution, so it is
// upsampled with the four nearest texels weighted by depth similarity: a plain bilinear lookup
// bleeds the occlusion of a far surface over a near silhouette (a halo around objects).
#include "../chunks/depth.glsl"
uniform highp Image occlusionTexture;
uniform highp vec2 occlusionSize; // occlusion target size in pixels
uniform highp float intensity;
uniform highp float power;

// Occlusion at `uv`, taken from the half-resolution texels that lie on the same surface.
highp float upsample(highp vec2 uv) {
    highp float z = viewDepth(snapToDepthTexel(uv));
    highp vec2 grid = uv * occlusionSize - .5;
    highp vec2 base = floor(grid);
    highp vec2 f = grid - base;
    highp float sum = 0.0, weights = 0.0, nearest = 1.0, nearestGap = 1e30;
    highp float tolerance = .05 * abs(z) + .02;
    for (int j = 0; j < 2; j++) {
        for (int i = 0; i < 2; i++) {
            highp vec2 tap = (base + vec2(float(i), float(j)) + .5) / occlusionSize;
            highp float value = Texel(occlusionTexture, tap).r;
            highp float gap = abs(viewDepth(snapToDepthTexel(tap)) - z);
            highp float bilinear = (i == 0 ? 1.0 - f.x : f.x) * (j == 0 ? 1.0 - f.y : f.y);
            highp float w = bilinear * (1.0 - smoothstep(0.0, tolerance, gap));
            sum += value * w;
            weights += w;
            if (gap < nearestGap) {
                nearestGap = gap;
                nearest = value;
            }
        }
    }
    // Every tap across an edge: fall back to the tap that is closest in depth.
    return weights > 1e-3 ? sum / weights : nearest;
}

// Strength curve. Up to 1 it fades the occlusion linearly; above 1 it deepens it without the
// hard clip that turned every moderately occluded pixel black: occlusion 1 stays 1, small
// occlusion grows `intensity` times faster.
highp float strength(highp float occlusion) {
    if (intensity <= 1.0) {
        return occlusion * intensity;
    }
    return occlusion * intensity / (1.0 + occlusion * (intensity - 1.0));
}

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    vec4 c = Texel(image, uv);
    highp float ao = pow(clamp(isSkyDepth(uv) ? 1.0 : upsample(uv), 0., 1.), power);
    ao = clamp(1.0 - strength(1.0 - ao), 0.0, 1.0);
    return vec4(c.rgb * ao, c.a);
}
