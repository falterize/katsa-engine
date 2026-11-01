uniform highp float time;
uniform highp vec2 resolution;
uniform highp vec2 regionOrigin;
uniform highp vec2 regionExtent;
uniform highp float noiseStrength;
uniform highp float scanlineStrength;
uniform highp float distortion;
highp float hash(highp vec2 p) {
    // Bound the input before arithmetic; mediump sine hashes overflow at phone resolutions.
    highp vec3 q=fract(vec3(mod(p,289.0).xyx)*0.1031);
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
vec4 effect(vec4 color, Image image, highp vec2 uv, highp vec2 screen) {
    highp vec2 size=max(regionExtent,vec2(1.0));
    highp vec2 dimensions=max(resolution,vec2(1.0));
    highp vec2 localUV=(uv*dimensions-regionOrigin)/size;
    highp float tick=mod(floor(time*24.0),4096.0);
    highp float jitter=(hash(vec2(floor(localUV.y*size.y/3.0),tick))-0.5)*distortion;
    localUV.x=clamp(localUV.x+jitter,0.0,1.0);
    highp vec2 sampleUV=(regionOrigin+localUV*size)/dimensions;
    vec4 source=Texel(image,sampleUV)*color;
    highp float noise=hash(floor(localUV*size/2.0)+tick);
    highp float scan=0.5+0.5*cos(mod(localUV.y*size.y,2.0)*3.14159265);
    source.rgb=mix(source.rgb,vec3(noise)*source.a,clamp(noiseStrength,0.0,1.0));
    source.rgb*=1.0-clamp(scanlineStrength,0.0,1.0)*scan;
    return source;
}
