vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    vec4 source=Texel(image,uv)*color;
    return vec4(vec3(source.a)-source.rgb,source.a);
}
