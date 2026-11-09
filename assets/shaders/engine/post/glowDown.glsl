// Glow: bright-pass and downsample. `firstLevel` extracts the bright part of the image
// (Godot's hdr threshold, scale and bloom), later levels only average the previous one.
uniform highp vec2 texel;         // one source pixel in uv units
uniform bool firstLevel;
uniform highp float threshold;
uniform highp float scale;
uniform highp float bloom;
highp vec3 bright(highp vec3 c) {
    highp float lum=dot(c,vec3(.2126,.7152,.0722));
    highp float over=max(lum-threshold,0.0);
    highp float gain=bloom+scale*over/max(lum,1e-4);
    return c*clamp(gain,0.0,8.0);
}
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    highp vec3 a=Texel(image,uv+texel*vec2(-1.,-1.)).rgb;
    highp vec3 b=Texel(image,uv+texel*vec2(1.,-1.)).rgb;
    highp vec3 c=Texel(image,uv+texel*vec2(-1.,1.)).rgb;
    highp vec3 d=Texel(image,uv+texel*vec2(1.,1.)).rgb;
    if(firstLevel) return vec4((bright(a)+bright(b)+bright(c)+bright(d))*.25,1.0);
    return vec4((a+b+c+d)*.25,1.0);
}
