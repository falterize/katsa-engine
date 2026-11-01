vec4 effect(vec4 color, Image textureImage, vec2 uv, vec2 pixel) {
    if(Texel(textureImage,uv).a < 0.01) discard;
    return vec4(1.0);
}
