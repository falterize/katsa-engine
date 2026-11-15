// Scene depth helpers for post passes. Pixel stage only.
//
// depthTexture holds the main pass depth (0..1). `depthRange` is (projection[11], projection[12])
// of the camera, which is all that is needed to turn a stored depth back into view-space z.
uniform highp Image depthTexture;
uniform highp vec2 depthRange;
uniform bool orthographic;
uniform highp vec2 depthSize; // depth texture size in pixels

// The centre of the depth texel `uv` falls in. Post targets can be smaller than the depth
// texture, so their pixel centres land exactly on texel borders, where a nearest lookup picks
// either neighbour depending on rounding. Reading neighbours from snapped centres is exact.
highp vec2 snapToDepthTexel(highp vec2 uv) {
    return (floor(uv * depthSize) + .5) / depthSize;
}

// Depth of the surface at `uv`, in view units along the camera axis.
highp float viewDepth(highp vec2 uv) {
    highp float d = Texel(depthTexture, uv).r * 2.0 - 1.0;
    if (orthographic) {
        return (d - depthRange.y) / depthRange.x;
    }
    return depthRange.y / (d - depthRange.x);
}

// Pixels the depth buffer cleared to its far value show the sky or nothing at all.
bool isSkyDepth(highp vec2 uv) {
    return Texel(depthTexture, uv).r >= .99999;
}

// Cheap per-pixel hash in 0..1 used to rotate sample patterns (interleaved gradient noise).
highp float screenNoise(highp vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(.06711056, .00583715))));
}
