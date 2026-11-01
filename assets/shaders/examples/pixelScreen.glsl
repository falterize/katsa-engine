uniform vec2 resolution;
uniform vec2 regionOrigin;
uniform vec2 regionExtent;
uniform float pixelSize;
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    float block=max(1.0,pixelSize);
    vec2 localPixel=uv*resolution-regionOrigin;
    vec2 center=(floor(localPixel/block)+0.5)*block;
    center=clamp(center,vec2(0.5),max(vec2(0.5),regionExtent-vec2(0.5)));
    return Texel(image,(regionOrigin+center)/resolution)*color;
}
