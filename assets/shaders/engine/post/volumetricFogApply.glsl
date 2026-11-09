// Composites the fog target over the image: scene * transmittance + scattered light.
uniform highp Image fogTexture;
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    vec4 c=Texel(image,uv);
    vec4 fog=Texel(fogTexture,uv);
    return vec4(c.rgb*fog.a+fog.rgb,c.a);
}
