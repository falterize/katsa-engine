#ifdef PIXEL
uniform highp vec3 right;
uniform highp vec3 up;
uniform highp vec3 forward;
uniform highp vec2 viewSize;
uniform highp float focal;
uniform highp vec2 edgeInset;
uniform bool panorama;
uniform highp vec4 tint;
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    highp vec3 ray=right*((uv.x-.5)*viewSize.x/focal)+up*((.5-uv.y)*viewSize.y/focal)+forward;
    highp vec2 sampleUV;
    if(panorama) {
        highp vec3 d=normalize(ray);
        sampleUV=vec2(fract(.5+atan(d.x,d.z)/6.28318530718),.5-asin(clamp(d.y,-1.,1.))/3.14159265359);
        sampleUV=clamp(sampleUV,edgeInset,vec2(1.)-edgeInset);
    } else {
        highp vec3 a=abs(ray);highp vec2 cell;highp vec2 p;
        if(a.x>=a.y && a.x>=a.z) {
            if(ray.x>0.) {cell=vec2(2.,1.);p=vec2(-ray.z,-ray.y)/a.x;}
            else {cell=vec2(0.,1.);p=vec2(ray.z,-ray.y)/a.x;}
        } else if(a.y>=a.z) {
            if(ray.y>0.) {cell=vec2(1.,0.);p=vec2(ray.x,ray.z)/a.y;}
            else {cell=vec2(1.,2.);p=vec2(ray.x,-ray.z)/a.y;}
        } else {
            if(ray.z>0.) {cell=vec2(1.,1.);p=vec2(ray.x,-ray.y)/a.z;}
            else {cell=vec2(3.,1.);p=vec2(-ray.x,-ray.y)/a.z;}
        }
        p=clamp(p*.5+.5,edgeInset,vec2(1.)-edgeInset);
        sampleUV=(cell+p)/vec2(4.,3.);
    }
    return vec4(Texel(image,sampleUV).rgb*tint.rgb*tint.a,1.);
}
#endif
