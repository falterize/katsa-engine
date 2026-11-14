// Final colour pass: glow blend, adjustments (brightness, contrast, saturation, colour
// correction lookup table), in one read of the image.
uniform bool glowEnabled;
uniform highp Image glowTexture;
uniform highp float glowIntensity;
uniform highp float glowMix;
uniform int glowMode; // 0 additive, 1 screen, 2 softlight, 3 replace, 4 mix
uniform bool adjustEnabled;
uniform highp vec3 adjust; // brightness, contrast, saturation
uniform bool lutEnabled;
uniform highp Image lutTexture;
uniform highp float lutSize; // slices per side
uniform highp float lutStrength;

// The lookup table is a strip of `lutSize` slices (blue axis); blend the two nearest slices.
highp vec3 lookup(highp vec3 c) {
    highp vec3 v = clamp(c, 0.0, 1.0) * (lutSize - 1.0);
    highp float slice = floor(v.b), next = min(slice + 1.0, lutSize - 1.0), f = v.b - slice;
    highp vec2 inner = (v.rg + .5) / vec2(lutSize * lutSize, lutSize);
    highp vec3 a = Texel(lutTexture, inner + vec2(slice / lutSize, 0.)).rgb;
    highp vec3 b = Texel(lutTexture, inner + vec2(next / lutSize, 0.)).rgb;
    return mix(a, b, f);
}

highp vec3 softlight(highp vec3 base, highp vec3 over) {
    return mix(
        2.0 * base * over + base * base * (1.0 - 2.0 * over),
        sqrt(base) * (2.0 * over - 1.0) + 2.0 * base * (1.0 - over),
        step(.5, over)
    );
}

highp vec3 blendGlow(highp vec3 c, highp vec3 glow) {
    if (glowMode == 0) {
        return c + glow;
    }
    if (glowMode == 1) {
        return 1.0 - (1.0 - c) * (1.0 - clamp(glow, 0.0, 1.0));
    }
    if (glowMode == 2) {
        // .5 is neutral: no glow, no change.
        return softlight(clamp(c, 0.0, 1.0), .5 + .5 * clamp(glow, 0.0, 1.0));
    }
    if (glowMode == 3) {
        return mix(c, glow, clamp(glowIntensity, 0.0, 1.0));
    }
    return mix(c, glow, glowMix);
}

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    vec4 source = Texel(image, uv);
    highp vec3 c = source.rgb;
    if (glowEnabled) {
        c = blendGlow(c, Texel(glowTexture, uv).rgb * glowIntensity);
    }
    if (adjustEnabled) {
        c *= adjust.x;
        c = (c - .5) * adjust.y + .5;
        highp float luminance = dot(c, vec3(.2126, .7152, .0722));
        c = mix(vec3(luminance), c, adjust.z);
    }
    if (lutEnabled) {
        c = mix(c, lookup(c), lutStrength);
    }
    return vec4(clamp(c, 0.0, 1.0), source.a);
}
