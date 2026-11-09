// Depth-aware blur of the occlusion target (run once per axis).
uniform highp Image depthTexture;
uniform highp vec2 direction;   // one texel step along the blur axis
uniform highp vec2 depthRange;  // projection[11], projection[12]
uniform bool orthographic;

highp float viewDepth(highp vec2 uv) {
    highp float d=Texel(depthTexture,uv).r*2.0-1.0;
    if(orthographic) return (d-depthRange.y)/depthRange.x;
    return depthRange.y/(d-depthRange.x);
}
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    highp float centerZ=viewDepth(uv);
    highp float sum=Texel(image,uv).r,weights=1.0;
    for(int i=1;i<=3;i++) {
        for(int s=-1;s<=1;s+=2) {
            highp vec2 at=uv+direction*float(i*s);
            highp float w=1.0-smoothstep(0.0,.05*abs(centerZ)+.02,abs(viewDepth(at)-centerZ));
            w*=1.0-float(i)*.2;
            sum+=Texel(image,at).r*w;
            weights+=w;
        }
    }
    return vec4(vec3(sum/weights),1.0);
}
