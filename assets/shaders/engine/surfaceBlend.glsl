#pragma language glsl3
// Accumulates one surface appearance channel into the blend target.
//
// A surface that blends between appearances renders each channel (colour, normal, roughness,
// metalness, occlusion, emission) separately and adds it scaled by `weight`.
#ifdef STAGE_PIXEL
uniform float weight;
uniform int channel;
uniform vec4 factor;
uniform bool opaque;
uniform vec2 imageUVScale;
uniform vec2 imageUVOffset;
uniform Image accumulatedMap;

const int channelColor = 0;
const int channelNormal = 1;
const int channelRoughness = 2;
const int channelMetalness = 3;
const int channelOcclusion = 4;

vec4 encodeChannel(vec4 texel) {
    if (channel == channelColor) {
        texel.rgb *= factor.rgb;
        if (opaque) {
            texel.a = 1.0;
        }
        return texel;
    }
    if (channel == channelNormal) {
        vec3 n = texel.rgb * 2.0 - 1.0;
        n.xy *= factor.x;
        return vec4(normalize(n) * .5 + .5, 1.0);
    }
    if (channel == channelRoughness || channel == channelMetalness) {
        return vec4(vec3(texel.r * factor.x), 1.0);
    }
    if (channel == channelOcclusion) {
        return vec4(vec3(mix(1.0, texel.r, factor.x)), 1.0);
    }
    // Emission: colour scaled by the factor colour and its intensity in alpha.
    return vec4(texel.rgb * factor.rgb * factor.a, 1.0);
}

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    vec4 previous = Texel(accumulatedMap, uv);
    vec4 texel = Texel(image, uv * imageUVScale + imageUVOffset);
    return previous + encodeChannel(texel) * weight;
}
#endif
