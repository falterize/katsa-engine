uniform highp float materialTime;
uniform vec3 accent;
vec4 effect(vec4 color, Image textureImage, vec2 uv, vec2 screen) {
    vec4 pixel = Texel(textureImage, uv) * color;
    float pulse = 0.12 + 0.10 * sin(materialTime * 2.0);
    pixel.rgb = mix(pixel.rgb, accent, pulse);
    return pixel;
}
