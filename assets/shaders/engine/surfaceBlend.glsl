#ifdef PIXEL
uniform float weight;
uniform int channel;
uniform vec4 factor;
uniform bool opaque;
uniform vec2 imageUVScale;
uniform vec2 imageUVOffset;
uniform Image accumulatedMap;
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    vec4 previous = Texel(accumulatedMap, uv);
    vec4 v=Texel(image,uv*imageUVScale+imageUVOffset);
    if(channel==0){v.rgb*=factor.rgb;if(opaque)v.a=1.0;}
    else if(channel==1){vec3 n=v.rgb*2.0-1.0;n.xy*=factor.x;v=vec4(normalize(n)*.5+.5,1.0);}
    else if(channel==2 || channel==3){v=vec4(vec3(v.r*factor.x),1.0);}
    else if(channel==4){v=vec4(vec3(mix(1.0,v.r,factor.x)),1.0);}
    else {v=vec4(v.rgb*factor.rgb*factor.a,1.0);}
    return previous + v*weight;
}
#endif
