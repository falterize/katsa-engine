// Multiplies the occlusion into the image.
uniform highp Image occlusionTexture;
uniform highp float intensity;
uniform highp float power;
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    vec4 c=Texel(image,uv);
    highp float ao=pow(clamp(Texel(occlusionTexture,uv).r,0.,1.),power);
    ao=clamp(1.0-(1.0-ao)*intensity,0.0,1.0);
    return vec4(c.rgb*ao,c.a);
}
