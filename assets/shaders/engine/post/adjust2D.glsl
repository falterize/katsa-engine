// World2D Adjustments: brightness, contrast and saturation of the finished plane picture. The
// plane canvas holds premultiplied colour, so the colour is divided by alpha first.
uniform highp vec3 adjust;        // brightness, contrast, saturation
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    vec4 src=Texel(image,uv);
    highp vec3 c=src.a>0.0 ? src.rgb/src.a : src.rgb;
    c*=adjust.x;
    c=(c-.5)*adjust.y+.5;
    highp float lum=dot(c,vec3(.2126,.7152,.0722));
    c=mix(vec3(lum),c,adjust.z);
    return vec4(clamp(c,0.0,1.0)*src.a,src.a)*color;
}
