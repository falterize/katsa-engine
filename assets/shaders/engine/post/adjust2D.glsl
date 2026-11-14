// World2D Adjustments: brightness, contrast and saturation of the finished plane picture. The
// plane canvas holds premultiplied colour, so the colour is divided by alpha first.
uniform highp vec3 adjust; // brightness, contrast, saturation

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    vec4 source = Texel(image, uv);
    highp vec3 c = source.a > 0.0 ? source.rgb / source.a : source.rgb;
    c *= adjust.x;
    c = (c - .5) * adjust.y + .5;
    highp float luminance = dot(c, vec3(.2126, .7152, .0722));
    c = mix(vec3(luminance), c, adjust.z);
    return vec4(clamp(c, 0.0, 1.0) * source.a, source.a) * color;
}
