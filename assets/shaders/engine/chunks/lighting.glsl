// The per-fragment light loop. Pixel stage only; included after the user code.
//
// shadeLights() walks the selected lights, resolves shadows and cones, and hands each light to
// applyLight(): the engine's default Lambert + GGX, or the user's light() function when a shader
// defines one. Surface state lives in the file-scope `surface*` variables so the user function
// receives exactly the built-ins documented in docs/guides/rendering/shaders.md.
uniform highp vec4 lightPosition[32];
uniform highp vec4 lightDirection[32];
uniform highp vec4 lightColor[32];
uniform highp vec4 lightExtra[32];
#specialize int lightCount
#ifdef KATSA_LIGHT_MASK
uniform bool objectLightMaskEnabled;
#endif
#specialize bool unlit

highp vec3 surfaceNormal;
highp vec3 surfaceView;
vec3 surfaceAlbedo;
vec3 surfaceF0;
vec4 surfaceTerms;
float surfaceRoughness;
float surfaceMetalness;
bool surfacePbr;
vec3 diffuseLight;
vec3 specularLight;
float debugVisibility;

// `toward` points at the light, `color` is colour * intensity, `attenuation` folds in the cone,
// distance falloff and shadow visibility.
void applyLight(highp vec3 toward, vec3 color, float attenuation) {
#ifdef KATSA_USER_LIGHT
    highp vec3 NORMAL = surfaceNormal;
    highp vec3 VIEW = surfaceView;
    highp vec3 LIGHT = toward;
    vec3 LIGHT_COLOR = color;
    float ATTENUATION = attenuation;
    vec3 ALBEDO = surfaceAlbedo;
    float ROUGHNESS = surfaceRoughness;
    float METALLIC = surfaceMetalness;
    highp float TIME = time;
    vec3 DIFFUSE_LIGHT = vec3(0.0);
    vec3 SPECULAR_LIGHT = vec3(0.0);
    KATSA_USER_LIGHT;
    diffuseLight += DIFFUSE_LIGHT;
    specularLight += SPECULAR_LIGHT;
#else
    diffuseLight += color * attenuation * max(0.0, dot(surfaceNormal, toward));
    if (surfacePbr) {
        specularLight += color * attenuation
            * preparedMaterialSpecular(surfaceNormal, toward, surfaceView, surfaceF0, surfaceTerms);
    }
#endif
}

// A user light() shades the whole sphere of directions (wrap lighting, toon ramps), so the
// back-face early-out below only applies to the default model, which is zero there anyway.
bool facesLight(highp vec3 toward) {
#ifdef KATSA_USER_LIGHT
    return true;
#else
    return dot(surfaceNormal, toward) > 0.0;
#endif
}

void shadeLights(highp vec3 shadowNormal, float shadowWeight, uint lightMask) {
    for (int i = 0; i < lightCount; i++) {
        if (unlit) {
            break;
        }
#ifdef KATSA_LIGHT_MASK
        if (objectLightMaskEnabled && (lightMask & (1u << uint(i))) == 0u) {
            continue;
        }
#endif
#ifndef KATSA_NO_DIRECTIONAL
        if (lightExtra[i].y > 1.5) {
            vec3 toward = -lightDirection[i].xyz;
            if (!facesLight(toward)) {
                continue;
            }
            float visibility = 1.0;
            if (receiveShadow && shadowWeight > 0.0 && lightShadowData[i].x >= 0.0) {
                visibility = mix(
                    1.0,
                    directionalVisibility(i, shadowNormal, toward),
                    shadowWeight * shadowLightFade[i]
                );
                debugVisibility = min(debugVisibility, visibility);
            }
            applyLight(toward, lightColor[i].rgb * lightColor[i].w, visibility);
            continue;
        }
#endif
        highp vec3 delta = (lightPosition[i].xyz - worldPosition) / max(lightPosition[i].w, 0.001);
        if (dot(delta, delta) > 1.0) {
            continue;
        }
        highp float distanceToLight = length(delta);
        highp vec3 toward = delta / max(distanceToLight, 0.00001);
        if (!facesLight(toward)) {
            continue;
        }
        float cone = 1.0;
        if (lightExtra[i].y < 0.5) {
            cone = smoothstep(lightDirection[i].w, lightExtra[i].x, dot(-toward, lightDirection[i].xyz));
        }
        if (cone <= 0.0) {
            continue;
        }
        highp float falloff = max(0.0, 1.0 - distanceToLight);
        if (lightExtra[i].y > 0.5) {
            falloff = max(
                0.0,
                1.0 - max(distanceToLight - lightExtra[i].x, 0.0) / max(1.0 - lightExtra[i].x, 0.001)
            );
        }
        vec3 sampledColor = lightColor[i].rgb;
        if (lightExtra[i].z > 0.5) {
            sampledColor *= 0.5 + 0.5 * sin(vec3(time * 0.8) + vec3(0.0, 2.094395, 4.18879));
        }
        float visibility = 1.0;
        if (receiveShadow && shadowWeight > 0.0 && lightShadowData[i].x >= 0.0) {
            int side = lightShadowData[i].y > 0.5
                ? pointShadowFace(worldPosition - shadowLightPosition[i].xyz)
                : 0;
            int face = int(lightShadowData[i].x) + side;
            if ((int(lightShadowData[i].z) & (1 << side)) != 0) {
                visibility = mix(
                    1.0,
                    shadowVisibility(
                        face,
                        localShadowProjection(i, side, shadowNormal),
                        shadowNormal,
                        toward,
                        false,
                        0
                    ),
                    shadowWeight * shadowLightFade[i]
                );
                debugVisibility = min(debugVisibility, visibility);
            }
        }
        applyLight(toward, sampledColor * lightColor[i].w, visibility * cone * falloff * falloff);
    }
}
