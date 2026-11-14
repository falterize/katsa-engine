// Distance fog and the final tone curve. Pixel stage only.
#specialize bool systemFogEnabled
#specialize bool systemToneMappingEnabled
uniform vec4 fogColor;
uniform highp vec4 fogSettings;
uniform bool toneMapping;
uniform float exposure;

vec3 applyToneMapping(vec3 color) {
    if (toneMapping && systemToneMappingEnabled) {
        return color * exposure / (vec3(1.0) + color * exposure);
    }
    return color;
}

// fogSettings = (density, start offset, end distance, linear ? 1 : 0); fogColor.a is the cap.
// `detach` (1 - lightInfluence) fades the fog out together with the lighting.
vec3 applyFog(vec3 color, highp float cameraDistance, float detach) {
    if (!systemFogEnabled) {
        return color;
    }
    highp float d = max(0.0, cameraDistance - fogSettings.y);
    highp float fog = 1.0 - exp(-max(fogSettings.x, 0.0) * d);
    if (fogSettings.w > 0.5) {
        fog = d / max(fogSettings.z - fogSettings.y, 0.001);
    }
    fog = clamp(fog, 0.0, fogColor.a) * (1.0 - detach);
    return mix(color, fogColor.rgb, fog);
}
