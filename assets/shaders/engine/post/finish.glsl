// Final colour pass: glow blend, adjustments (brightness, contrast, saturation, colour
// correction lookup table) and vignette, in one read of the image.
uniform bool glowEnabled;
uniform highp Image glowTexture;
uniform highp float glowIntensity;
uniform highp float glowMix;
uniform int glowMode;             // 0 additive, 1 screen, 2 softlight, 3 replace, 4 mix
uniform bool adjustEnabled;
uniform highp vec3 adjust;        // brightness, contrast, saturation
uniform bool lutEnabled;
uniform highp Image lutTexture;
uniform highp float lutSize;      // slices per side
uniform highp float lutStrength;
uniform bool vignetteEnabled;
uniform highp vec3 vignette;      // intensity, radius, softness
uniform highp float aspect;

highp vec3 lookup(highp vec3 c) {
    highp vec3 v=clamp(c,0.0,1.0)*(lutSize-1.0);
    highp float slice=floor(v.b),next=min(slice+1.0,lutSize-1.0),f=v.b-slice;
    highp vec2 inner=(v.rg+.5)/vec2(lutSize*lutSize,lutSize);
    highp vec3 a=Texel(lutTexture,inner+vec2(slice/lutSize,0.)).rgb;
    highp vec3 b=Texel(lutTexture,inner+vec2(next/lutSize,0.)).rgb;
    return mix(a,b,f);
}
highp vec3 softlight(highp vec3 base,highp vec3 over) {
    return mix(2.0*base*over+base*base*(1.0-2.0*over),
        sqrt(base)*(2.0*over-1.0)+2.0*base*(1.0-over),step(.5,over));
}
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    vec4 src=Texel(image,uv);
    highp vec3 c=src.rgb;
    if(glowEnabled) {
        highp vec3 g=Texel(glowTexture,uv).rgb*glowIntensity;
        if(glowMode==0) c+=g;
        else if(glowMode==1) c=1.0-(1.0-c)*(1.0-clamp(g,0.0,1.0));
        else if(glowMode==2) c=softlight(clamp(c,0.0,1.0),clamp(g,0.0,1.0));
        else if(glowMode==3) c=mix(c,g,clamp(glowIntensity,0.0,1.0));
        else c=mix(c,g,glowMix);
    }
    if(adjustEnabled) {
        c*=adjust.x;
        c=(c-.5)*adjust.y+.5;
        highp float lum=dot(c,vec3(.2126,.7152,.0722));
        c=mix(vec3(lum),c,adjust.z);
    }
    if(lutEnabled) c=mix(c,lookup(c),lutStrength);
    if(vignetteEnabled) {
        highp vec2 p=(uv-.5)*vec2(aspect,1.0)*2.0/max(aspect,1.0);
        highp float edge=smoothstep(vignette.y,vignette.y-vignette.z,length(p));
        c*=mix(1.0-vignette.x,1.0,edge);
    }
    return vec4(clamp(c,0.0,1.0),src.a);
}
