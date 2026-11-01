vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    return Texel(image,uv)*color;
}
