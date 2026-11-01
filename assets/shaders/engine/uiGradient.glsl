#pragma language glsl3
varying vec2 uiCanvasPosition;
#ifdef VERTEX
vec4 position(mat4 transformProjection,vec4 vertexPosition) {
    uiCanvasPosition=(TransformMatrix*vertexPosition).xy;
    return transformProjection*vertexPosition;
}
#endif
#ifdef PIXEL
uniform vec2 gradientOrigin;
uniform vec2 gradientExtent;
uniform vec2 gradientDirection;
uniform vec2 gradientOffset;
uniform vec4 gradientColors[16];
uniform float gradientTimes[16];
uniform int gradientCount;
uniform float gradientOpacity;
vec4 effect(vec4 color,Image inputTexture,vec2 uv,vec2 pixel) {
    vec2 p=(uiCanvasPosition-gradientOrigin)/max(gradientExtent,vec2(.0001))-.5-gradientOffset;
    float span=max(abs(gradientDirection.x)+abs(gradientDirection.y),.0001);
    float t=clamp(.5+dot(p,gradientDirection)/span,0.,1.);
    vec4 tint=gradientColors[0];
    for(int i=1;i<16;i++) {
        if(i>=gradientCount) break;
        float blend=clamp((t-gradientTimes[i-1])/max(.00001,gradientTimes[i]-gradientTimes[i-1]),0.,1.);
        if(t>=gradientTimes[i-1]) tint=mix(gradientColors[i-1],gradientColors[i],blend);
    }
    tint.a*=gradientOpacity;
    return Texel(inputTexture,uv)*color*tint;
}
#endif
