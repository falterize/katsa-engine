// Depth of field (Godot's far/near blur): the circle of confusion follows the distance from the
// camera; taps closer than the centre pixel's own blur are weighted down so a sharp foreground
// never bleeds into a blurred background.
uniform highp Image depthTexture;
uniform highp vec2 depthRange;    // projection[11], projection[12]
uniform bool orthographic;
uniform highp vec2 texel;         // one pixel of the image in uv units
uniform highp float maxRadius;    // blur radius in pixels
uniform bool farEnabled;
uniform highp vec2 farRange;      // distance, transition
uniform bool nearEnabled;
uniform highp vec2 nearRange;
uniform int sampleCount;

highp float viewDepth(highp vec2 uv) {
    highp float d=Texel(depthTexture,uv).r*2.0-1.0;
    if(orthographic) return (d-depthRange.y)/depthRange.x;
    return depthRange.y/(d-depthRange.x);
}
// 0 sharp .. 1 fully blurred; the sky counts as infinitely far.
highp float confusion(highp vec2 uv) {
    highp float raw=Texel(depthTexture,uv).r;
    highp float z=raw>=.99999 ? 1e6 : viewDepth(uv);
    highp float coc=0.0;
    if(farEnabled) coc=max(coc,clamp((z-farRange.x)/farRange.y,0.0,1.0));
    if(nearEnabled) coc=max(coc,clamp((nearRange.x-z)/nearRange.y,0.0,1.0));
    return coc;
}
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    vec4 center=Texel(image,uv);
    highp float coc=confusion(uv);
    highp float radius=coc*maxRadius;
    if(radius<.5) return center;
    highp vec3 sum=center.rgb;
    highp float weights=1.0;
    for(int i=0;i<32;i++) {
        if(i>=sampleCount) break;
        highp float f=(float(i)+.5)/float(sampleCount);
        highp float a=float(i)*2.3999632;
        highp vec2 offset=vec2(cos(a),sin(a))*sqrt(f)*radius;
        highp vec2 at=uv+offset*texel;
        highp float tapCoc=confusion(at);
        highp float reach=tapCoc*maxRadius;
        highp float w=clamp(reach/max(length(offset),1.0),0.0,1.0);
        sum+=Texel(image,at).rgb*w;
        weights+=w;
    }
    return vec4(sum/weights,center.a);
}
