uniform bool multiplyMode;
vec4 effect(vec4 color, Image textureImage, vec2 uv, vec2 screenPosition) {
    vec4 texel = Texel(textureImage, uv) * color;
    if (multiplyMode) return vec4(mix(vec3(1.0), texel.rgb, texel.a), 1.0);
    return texel;
}
