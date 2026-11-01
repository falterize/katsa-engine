// Spatial radial speed blur. This is not temporal, velocity-buffer motion blur.
uniform vec2 resolution;
uniform float strength;
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    vec2 d=(uv-vec2(.5))*clamp(strength,0.,.065);
    vec4 sum=vec4(0.);
    for(int i=0;i<7;i++)sum+=Texel(image,clamp(uv-d*(float(i)/6.),vec2(0.),vec2(1.)));
    return sum/7.*color;
}
