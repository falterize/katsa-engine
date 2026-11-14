#pragma language glsl3
// Gradient overlay for UI nodes: up to 16 colour stops along a direction, multiplied onto the
// node's own texture and colour. Stops are `gradientColors[i]` at `gradientTimes[i]` (0..1).
varying vec2 uiCanvasPosition;

#ifdef STAGE_VERTEX
vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    uiCanvasPosition = (TransformMatrix * vertexPosition).xy;
    return transformProjection * vertexPosition;
}
#endif

#ifdef STAGE_PIXEL
uniform vec2 gradientOrigin;
uniform vec2 gradientExtent;
uniform vec2 gradientDirection;
uniform vec2 gradientOffset;
uniform vec4 gradientColors[16];
uniform float gradientTimes[16];
uniform int gradientCount;
uniform float gradientOpacity;

// Position along the gradient axis, 0 at the start and 1 at the end.
float gradientPosition() {
    vec2 p = (uiCanvasPosition - gradientOrigin) / max(gradientExtent, vec2(.0001)) - .5
        - gradientOffset;
    float span = max(abs(gradientDirection.x) + abs(gradientDirection.y), .0001);
    return clamp(.5 + dot(p, gradientDirection) / span, 0., 1.);
}

vec4 effect(vec4 color, Image inputTexture, vec2 uv, vec2 pixel) {
    float t = gradientPosition();
    vec4 tint = gradientColors[0];
    for (int i = 1; i < 16; i++) {
        if (i >= gradientCount) {
            break;
        }
        float blend = clamp(
            (t - gradientTimes[i - 1]) / max(.00001, gradientTimes[i] - gradientTimes[i - 1]),
            0.,
            1.
        );
        if (t >= gradientTimes[i - 1]) {
            tint = mix(gradientColors[i - 1], gradientColors[i], blend);
        }
    }
    tint.a *= gradientOpacity;
    return Texel(inputTexture, uv) * color * tint;
}
#endif
