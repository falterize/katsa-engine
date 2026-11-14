#pragma language glsl3
// Billboard sprites for particles, beams and trails (also ribbons).
//
// Vertices arrive in world space, so the spatial built-ins are: MODEL_MATRIX = identity,
// VERTEX = the world position, NORMAL = the sprite facing. fragment() runs before the
// per-light shading and light() is not used: sprites take the simple light model below.
varying highp vec3 particleWorldPosition;
uniform highp float time;
uniform highp vec2 viewportSize;
uniform highp vec3 cameraPosition;
uniform highp mat4 viewMatrix;
uniform highp mat4 projectionMatrix;

#user_code

#ifdef STAGE_VERTEX
uniform highp mat4 viewProjection;

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    highp vec4 world = vertexPosition;
#ifdef KATSA_USER_VERTEX
    highp vec3 VERTEX = world.xyz;
    highp vec3 NORMAL = vec3(0.0, 0.0, 1.0);
    vec2 UV = VaryingTexCoord.st;
    vec4 COLOR = VaryingColor;
    highp mat4 MODEL_MATRIX = mat4(1.0);
    highp mat4 VIEW_MATRIX = viewMatrix;
    highp mat4 PROJECTION_MATRIX = projectionMatrix;
    highp mat4 MODELVIEW_MATRIX = viewMatrix;
    highp float TIME = time;
    highp vec2 VIEWPORT_SIZE = viewportSize;
    highp vec3 CAMERA_POSITION = cameraPosition;
    highp vec4 POSITION = vec4(0.0);
    KATSA_USER_VERTEX;
    world.xyz = VERTEX;
    VaryingTexCoord.st = UV;
    VaryingColor = COLOR;
#endif
    particleWorldPosition = world.xyz;
#ifdef KATSA_USER_POSITION
    return POSITION;
#else
    return viewProjection * world;
#endif
}
#endif

#ifdef STAGE_PIXEL
uniform bool multiplyMode;
// Shadow lookups read this copy: it is nudged toward the light so a particle never compares
// its own depth with the billboard its emitter casts into the atlas (self-shadow flicker).
highp vec3 particleShadowPosition;
uniform highp float particleShadowOffset;
#define worldPosition particleShadowPosition
#include "../chunks/shadowSampling.glsl"
uniform float particleShadowSlot[8];
uniform vec3 particleLighting;
uniform bool particleUnlit;
// Ribbons: 1 - lightInfluence, premultiplied output and light emission (0 = alpha, 1 = additive).
uniform float particleDetach;
uniform bool ribbonPremultiply;
uniform float ribbonEmission;
uniform float particleBrightness;
uniform vec3 particleFacing;
uniform int particleLightCount;
uniform vec4 particleLightPosition[8];
uniform vec4 particleLightColor[8];
uniform vec4 particleLightDirection[8];

// Light reaching the sprite: the ambient term plus every selected light, shadowed per light.
vec3 particleIncomingLight() {
    vec3 light = particleLighting;
    if (particleUnlit) {
        return light;
    }
    for (int i = 0; i < 8; i++) {
        if (i >= particleLightCount) {
            break;
        }
        int slot = int(particleShadowSlot[i]);
        if (particleLightPosition[i].w == 0.0) {
            vec3 direction = -particleLightDirection[i].xyz;
            particleShadowPosition = particleWorldPosition + direction * particleShadowOffset;
            float visibility = receiveShadow && slot >= 0 && lightShadowData[slot].x >= 0.0
                ? directionalVisibility(slot, particleFacing, direction)
                : 1.0;
            light += visibility * particleLightColor[i].rgb * particleLightColor[i].a
                * abs(dot(particleFacing, direction));
            continue;
        }
        vec3 delta = particleLightPosition[i].xyz - particleWorldPosition;
        float distance = length(delta), radius = max(.001, particleLightPosition[i].w);
        if (distance >= radius) {
            continue;
        }
        vec3 direction = delta / max(.001, distance);
        float cone = particleLightDirection[i].w < -1.0
            ? 1.0
            : smoothstep(
                particleLightDirection[i].w,
                min(.999, particleLightDirection[i].w + .1),
                dot(-direction, particleLightDirection[i].xyz)
            );
        float attenuation = 1.0 - distance / radius;
        float visibility = 1.0;
        particleShadowPosition = particleWorldPosition + direction * particleShadowOffset;
        if (receiveShadow && slot >= 0 && lightShadowData[slot].x >= 0.0) {
            int side = lightShadowData[slot].y > .5
                ? pointShadowFace(worldPosition - shadowLightPosition[slot].xyz)
                : 0;
            if ((int(lightShadowData[slot].z) & (1 << side)) != 0) {
                visibility = shadowVisibility(
                    int(lightShadowData[slot].x) + side,
                    localShadowProjection(slot, side, particleFacing),
                    particleFacing,
                    direction,
                    false,
                    0
                );
            }
        }
        light += visibility * particleLightColor[i].rgb * particleLightColor[i].a
            * attenuation * attenuation * cone * abs(dot(particleFacing, direction));
    }
    return light;
}

vec4 effect(vec4 color, Image spriteImage, vec2 uv, vec2 screenPosition) {
    vec4 texel = Texel(spriteImage, uv) * color;
    vec3 emission = vec3(0.0);
#ifdef KATSA_USER_FRAGMENT
    {
        highp vec4 FRAGCOORD = gl_FragCoord;
        vec2 UV = uv;
        vec2 UV_SCALE = vec2(1.0);
        vec2 UV_OFFSET = vec2(0.0);
        vec4 COLOR = color;
        highp vec3 WORLD_POSITION = particleWorldPosition;
        highp vec3 VIEW = normalize(cameraPosition - particleWorldPosition);
        bool FRONT_FACING = true;
        highp float TIME = time;
        vec4 MODULATE = vec4(1.0);
        vec3 ALBEDO = texel.rgb;
        float ALPHA = texel.a;
        highp vec3 NORMAL = particleFacing;
        float ROUGHNESS = 1.0;
        float METALLIC = 0.0;
        vec3 EMISSION = vec3(0.0);
        float AO = 1.0;
#define TEXTURE spriteImage
        KATSA_USER_FRAGMENT;
#undef TEXTURE
        texel = vec4(ALBEDO, ALPHA);
        emission = EMISSION;
    }
#endif
#ifdef KATSA_USER_UNSHADED
    vec3 result = texel.rgb + emission;
#else
    vec3 result = texel.rgb * mix(particleIncomingLight(), vec3(1.0), particleDetach)
            * particleBrightness
        + emission;
#endif
    if (ribbonPremultiply) {
        return vec4(result * texel.a, texel.a * (1.0 - ribbonEmission));
    }
    if (multiplyMode) {
        return vec4(mix(vec3(1.0), result, texel.a), 1.0);
    }
    return vec4(result, texel.a);
}
#endif
