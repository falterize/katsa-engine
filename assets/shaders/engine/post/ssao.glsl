// Screen-space ambient occlusion from the scene depth. Draws occlusion (1 = open) into a
// half-resolution target; the apply shader multiplies it into the image.
uniform highp Image depthTexture;
uniform highp vec2 depthSize;     // depth texture size in pixels
uniform highp vec2 viewSize;      // logical view size the focal length belongs to
uniform highp float focal;        // perspective focal length (view-size units)
uniform highp float pixelsPerUnit; // orthographic scale
uniform highp vec2 depthRange;    // projection[11], projection[12]
uniform bool orthographic;
uniform highp float radius;
uniform highp float bias;
uniform int sampleCount;

highp float viewDepth(highp vec2 uv) {
    highp float d=Texel(depthTexture,uv).r*2.0-1.0;
    if(orthographic) return (d-depthRange.y)/depthRange.x;
    return depthRange.y/(d-depthRange.x);
}
highp vec3 viewPosition(highp vec2 uv,highp float z) {
    highp vec2 centered=vec2(uv.x-.5,.5-uv.y)*viewSize;
    if(orthographic) return vec3(centered/pixelsPerUnit,z);
    return vec3(centered/focal*z,z);
}
highp vec2 viewToUV(highp vec3 p) {
    highp vec2 s;
    if(orthographic) s=p.xy*pixelsPerUnit/viewSize;
    else s=p.xy*focal/(max(p.z,1e-4)*viewSize);
    return vec2(.5+s.x,.5-s.y);
}
highp float noise(highp vec2 p) {
    return fract(52.9829189*fract(dot(p,vec2(.06711056,.00583715))));
}

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    highp vec2 texel=1.0/depthSize;
    highp float z=viewDepth(uv);
    // Sky and far clip carry no occluders.
    if(Texel(depthTexture,uv).r>=.99999) return vec4(1.0);
    highp vec3 p=viewPosition(uv,z);
    // Face normal from the smaller of the two depth steps on each axis.
    highp vec3 px1=viewPosition(uv+vec2(texel.x,0.),viewDepth(uv+vec2(texel.x,0.)));
    highp vec3 px0=viewPosition(uv-vec2(texel.x,0.),viewDepth(uv-vec2(texel.x,0.)));
    highp vec3 py1=viewPosition(uv+vec2(0.,texel.y),viewDepth(uv+vec2(0.,texel.y)));
    highp vec3 py0=viewPosition(uv-vec2(0.,texel.y),viewDepth(uv-vec2(0.,texel.y)));
    highp vec3 dx=abs(px1.z-p.z)<abs(p.z-px0.z) ? px1-p : p-px0;
    highp vec3 dy=abs(py1.z-p.z)<abs(p.z-py0.z) ? py1-p : p-py0;
    highp vec3 n=normalize(cross(dy,dx));
    if(n.z>0.0) n=-n; // face the camera (view space looks down +z)
    highp float angle=noise(screen)*6.2831853;
    highp float occlusion=0.0;
    for(int i=0;i<24;i++) {
        if(i>=sampleCount) break;
        highp float fi=(float(i)+.5)/float(sampleCount);
        highp float a=angle+float(i)*2.3999632; // golden angle spreads the taps
        highp vec3 dir=vec3(cos(a)*sqrt(fi),sin(a)*sqrt(fi),sqrt(1.0-fi));
        // Orient the tap into the hemisphere above the surface.
        highp vec3 t=normalize(abs(n.y)<.99 ? cross(n,vec3(0.,1.,0.)) : cross(n,vec3(1.,0.,0.)));
        highp vec3 b=cross(n,t);
        highp float scale=mix(.15,1.0,fi*fi);
        highp vec3 q=p+(t*dir.x+b*dir.y+n*dir.z)*radius*scale;
        highp vec2 quv=viewToUV(q);
        if(quv.x<0.||quv.x>1.||quv.y<0.||quv.y>1.) continue;
        highp float sceneZ=viewDepth(quv);
        highp float range=smoothstep(0.0,1.0,radius/max(abs(z-sceneZ),1e-4));
        // The bias grows with distance: a depth texel of a far, grazing surface spans many depth
        // steps, which showed up as bands on floors at low render density.
        occlusion+=(sceneZ<=q.z-bias-q.z*0.006 ? 1.0 : 0.0)*range;
    }
    return vec4(vec3(1.0-occlusion/float(sampleCount)),1.0);
}
