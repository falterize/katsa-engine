// FXAA: luma-edge direction blur on the finished image.
uniform highp vec2 texel;
highp float luma(highp vec3 c) { return dot(c,vec3(.299,.587,.114)); }
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    highp vec3 nw=Texel(image,uv+texel*vec2(-1.,-1.)).rgb;
    highp vec3 ne=Texel(image,uv+texel*vec2(1.,-1.)).rgb;
    highp vec3 sw=Texel(image,uv+texel*vec2(-1.,1.)).rgb;
    highp vec3 se=Texel(image,uv+texel*vec2(1.,1.)).rgb;
    vec4 mid=Texel(image,uv);
    highp float lNW=luma(nw),lNE=luma(ne),lSW=luma(sw),lSE=luma(se),lM=luma(mid.rgb);
    highp float lMin=min(lM,min(min(lNW,lNE),min(lSW,lSE)));
    highp float lMax=max(lM,max(max(lNW,lNE),max(lSW,lSE)));
    // Flat areas need no filtering.
    if(lMax-lMin<max(.0312,lMax*.125)) return mid;
    highp vec2 dir=vec2(-((lNW+lNE)-(lSW+lSE)),(lNW+lSW)-(lNE+lSE));
    highp float reduce=max((lNW+lNE+lSW+lSE)*.25*.125,1.0/128.0);
    highp float rcp=1.0/(min(abs(dir.x),abs(dir.y))+reduce);
    dir=clamp(dir*rcp,vec2(-8.),vec2(8.))*texel;
    highp vec3 a=.5*(Texel(image,uv+dir*(1.0/3.0-.5)).rgb+Texel(image,uv+dir*(2.0/3.0-.5)).rgb);
    highp vec3 b=a*.5+.25*(Texel(image,uv+dir*-.5).rgb+Texel(image,uv+dir*.5).rgb);
    highp float lB=luma(b);
    return vec4((lB<lMin||lB>lMax)?a:b,mid.a);
}
