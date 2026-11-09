// Glow: tent-filter upsample, added onto the next larger level.
uniform highp vec2 texel;         // one source pixel in uv units
uniform highp float spread;
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    highp vec2 o=texel*spread;
    highp vec3 sum=Texel(image,uv).rgb*4.0;
    sum+=Texel(image,uv+vec2(-o.x,0.)).rgb*2.0;
    sum+=Texel(image,uv+vec2(o.x,0.)).rgb*2.0;
    sum+=Texel(image,uv+vec2(0.,-o.y)).rgb*2.0;
    sum+=Texel(image,uv+vec2(0.,o.y)).rgb*2.0;
    sum+=Texel(image,uv+o*vec2(-1.,-1.)).rgb;
    sum+=Texel(image,uv+o*vec2(1.,-1.)).rgb;
    sum+=Texel(image,uv+o*vec2(-1.,1.)).rgb;
    sum+=Texel(image,uv+o*vec2(1.,1.)).rgb;
    return vec4(sum/16.0,1.0);
}
