#pragma language glsl3
// The spatial world program: draws Mesh3D objects, and sprite-less 3D geometry in general.
//
// One source builds every variant. The composer turns `#specialize` uniforms into constants
// and sets the KATSA_* flags (see source/engine/graphics/pipeline/shaderVariants.lua), then
// splices user shaders at `#user_code`:
//
//   vertex()   runs in the vertex stage after skinning, before the model matrix
//   fragment() runs after texturing and the surface maps, before lighting
//   light()    runs once per light in place of the default Lambert + GGX
//
// Flags: KATSA_SOLID (opaque, no alpha test), KATSA_EARLY_DEPTH, KATSA_LIGHT_MASK,
// KATSA_NO_DIRECTIONAL, KATSA_SHADOW_SAMPLES, plus the KATSA_USER_* flags the composer derives.
varying highp vec3 worldPosition;
varying highp vec3 worldNormal;
varying highp vec3 diagnosticPosition;
#ifdef KATSA_LIGHT_MASK
flat varying highp vec2 relevantLights;
#endif
uniform bool surfaceMissing;
uniform highp vec4 surfaceDiagnosticBounds;

// Frame uniforms every shader (and user shader) may read.
uniform highp float time;
uniform highp vec2 viewportSize;
uniform highp vec3 cameraPosition;
uniform highp mat4 viewMatrix;
uniform highp mat4 projectionMatrix;

#ifdef STAGE_PIXEL
#include "./chunks/pbr.glsl"
#endif

#ifdef STAGE_PIXEL
// View-space distance along the camera axis for a raw value read from a hint_depth_texture
// sampler (0..1). Works for perspective and orthographic cameras.
highp float linear_depth(highp float raw) {
    highp float ndc = raw * 2.0 - 1.0;
    if (projectionMatrix[3][3] > 0.5) {
        return (ndc - projectionMatrix[3][2]) / projectionMatrix[2][2];
    }
    return projectionMatrix[3][2] / (ndc - projectionMatrix[2][2]);
}
#endif

#user_code

#ifdef STAGE_VERTEX
#include "./chunks/mesh.glsl"
uniform highp mat4 viewProjection;
uniform highp mat3 objectNormalMatrix;
attribute highp vec3 vertexNormal;
attribute highp vec3 instanceNormal1;
attribute highp vec3 instanceNormal2;
attribute highp vec3 instanceNormal3;
#ifdef KATSA_LIGHT_MASK
uniform highp vec2 objectLights1;
attribute highp vec2 instanceLights1;
#endif

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
#ifdef KATSA_LIGHT_MASK
    relevantLights = instanced ? instanceLights1 : objectLights1;
#endif
    highp mat4 MODEL_MATRIX = meshModelMatrix();
    highp mat3 normalMatrix = objectNormalMatrix;
    if (instanced) {
        normalMatrix = transpose(mat3(instanceNormal1, instanceNormal2, instanceNormal3));
    } else if (skinEnabled) {
        // Skinned meshes derive the normal matrix from the model matrix sent with the same
        // draw, so it can never lag behind a stale per-object uniform.
        normalMatrix = transpose(inverse(mat3(MODEL_MATRIX)));
    }
    diagnosticPosition = surfaceMissing
        ? (vertexPosition.xyz - surfaceDiagnosticBounds.xyz) * surfaceDiagnosticBounds.w
        : vec3(0.0);
    highp vec4 localPosition = vertexPosition;
    highp vec3 localNormal = vertexNormal;
    if (skinEnabled) {
        highp mat4 deform = meshSkinMatrix();
        localPosition = deform * localPosition;
        localNormal = transpose(inverse(mat3(deform))) * localNormal;
    }
#ifdef KATSA_USER_VERTEX
    highp vec3 VERTEX = localPosition.xyz;
    highp vec3 NORMAL = localNormal;
    vec2 UV = VaryingTexCoord.st;
    vec4 COLOR = VaryingColor;
    highp mat4 VIEW_MATRIX = viewMatrix;
    highp mat4 PROJECTION_MATRIX = projectionMatrix;
    highp mat4 MODELVIEW_MATRIX = viewMatrix * MODEL_MATRIX;
    highp float TIME = time;
    highp vec2 VIEWPORT_SIZE = viewportSize;
    highp vec3 CAMERA_POSITION = cameraPosition;
    highp vec4 POSITION = vec4(0.0);
    KATSA_USER_VERTEX;
    localPosition.xyz = VERTEX;
    localNormal = NORMAL;
    VaryingTexCoord.st = UV;
    VaryingColor = COLOR;
#endif
    highp vec4 world = MODEL_MATRIX * localPosition;
    worldPosition = world.xyz;
    worldNormal = normalMatrix * localNormal;
#ifdef KATSA_USER_POSITION
    return POSITION;
#else
    return viewProjection * world;
#endif
}
#endif

#ifdef STAGE_PIXEL
#ifdef KATSA_EARLY_DEPTH
uniform highp Image depthPrepassTexture;
uniform highp vec2 depthPrepassSize;
uniform bool depthPrepassEnabled;
const highp float depthPrepassGuard = 2.0 / 16777215.0;
#endif
uniform bool shadowDebug;
uniform bool normalDebug;
// 1 - lightInfluence: 0 = fully lit (also when never sent), 1 = flat colour.
uniform float lightDetach;
#specialize bool canvasTexture
uniform vec4 tint;
uniform float alphaCutoff;
uniform vec3 ambient;
#include "./chunks/shadowSampling.glsl"
#include "./chunks/surface.glsl"
#include "./chunks/lighting.glsl"
#include "./chunks/fog.glsl"

vec4 effect(vec4 color, Image textureImage, vec2 uv, vec2 screenPosition) {
#ifdef KATSA_EARLY_DEPTH
    if (depthPrepassEnabled
        && gl_FragCoord.z > Texel(depthPrepassTexture, screenPosition / depthPrepassSize).r
                + depthPrepassGuard) {
        discard;
    }
#endif
    uv = uv * imageUVScale + imageUVOffset;
    uv = decalUV(uv);
    vec4 texel = Texel(textureImage, uv);
    if (canvasTexture && texel.a > 0.0) {
        texel.rgb /= texel.a;
    }
    if (surfaceEnabled) {
        texel.rgb *= surfaceColor;
        if (surfaceOpaque) {
            texel.a = 1.0;
        }
    }
    texel *= tint * color;
#if !defined(KATSA_SOLID) && !defined(KATSA_USER_FRAGMENT)
    if (texel.a <= alphaCutoff) {
        discard;
    }
#endif
    // Diagnostic material remains recognizable even when the mesh has no authored UVs.
    if (surfaceMissing) {
        float cell = mod(dot(floor(diagnosticPosition), vec3(1.0)), 2.0);
        return vec4(mix(vec3(0.0), vec3(0.7, 0.0, 0.9), cell), texel.a);
    }
    highp vec3 normal = normalize(worldNormal);
    if (!gl_FrontFacing) {
        normal = -normal;
    }
    // Shadow slope and offset use the true facet normal: the interpolated shading normal of a
    // smooth mesh disagrees with the depth-map surface near the terminator and produces acne.
    highp vec3 facet = cross(dFdx(worldPosition), dFdy(worldPosition));
    highp vec3 shadowNormal = dot(facet, facet) > 0.0 ? normalize(facet) : normal;
    if (dot(shadowNormal, normal) < 0.0) {
        shadowNormal = -shadowNormal;
    }
    highp vec3 viewDirection = normalize(cameraPosition - worldPosition);
    SurfaceMaps maps = sampleSurfaceMaps(uv, texel.rgb, normal);
    normal = maps.normal;

#ifdef KATSA_USER_FRAGMENT
    {
        highp vec4 FRAGCOORD = gl_FragCoord;
        vec2 SCREEN_UV = gl_FragCoord.xy / viewportSize;
        vec2 UV = uv;
        vec2 UV_SCALE = imageUVScale;
        vec2 UV_OFFSET = imageUVOffset;
        vec4 COLOR = color;
        highp vec3 WORLD_POSITION = worldPosition;
        highp vec3 VIEW = viewDirection;
        bool FRONT_FACING = gl_FrontFacing;
        highp float TIME = time;
        vec4 MODULATE = tint;
        vec3 ALBEDO = texel.rgb;
        float ALPHA = texel.a;
        highp vec3 NORMAL = normal;
        float ROUGHNESS = maps.roughness;
        float METALLIC = maps.metalness;
        vec3 EMISSION = maps.emission;
        float AO = maps.occlusion;
#define TEXTURE textureImage
        KATSA_USER_FRAGMENT;
#undef TEXTURE
        texel = vec4(ALBEDO, ALPHA);
        normal = normalize(NORMAL);
        maps.roughness = clamp(ROUGHNESS, .04, 1.0);
        maps.metalness = clamp(METALLIC, 0.0, 1.0);
        maps.emission = EMISSION;
        maps.occlusion = AO;
        maps.f0 = mix(vec3(.04), texel.rgb, maps.metalness);
    }
#if !defined(KATSA_SOLID) || defined(KATSA_USER_ALPHA)
    if (texel.a <= alphaCutoff) {
        discard;
    }
#endif
#endif

    surfaceNormal = normal;
    surfaceView = viewDirection;
    surfaceAlbedo = texel.rgb;
    surfaceF0 = maps.f0;
    surfaceRoughness = maps.roughness;
    surfaceMetalness = maps.metalness;
    surfaceTerms = materialSpecularTerms(normal, viewDirection, maps.roughness);
    surfacePbr = surfaceEnabled;
#ifdef KATSA_USER_PBR
    surfacePbr = true;
#endif
    highp float cameraDistance = length(worldPosition - cameraPosition);
    highp float fadeWidth = max(shadowFadeDistance, 0.001);
    float shadowWeight = 1.0
        - smoothstep(max(0.0, shadowDistance - fadeWidth), shadowDistance, cameraDistance);
    diffuseLight = unlit ? vec3(1.0) : ambient * maps.occlusion;
    specularLight = vec3(0.0);
    debugVisibility = 2.0;
    uint lightMask = 0u;
#ifdef KATSA_LIGHT_MASK
    lightMask = uint(relevantLights.x) | (uint(relevantLights.y) << 16u);
#endif
#ifndef KATSA_USER_UNSHADED
    shadeLights(shadowNormal, shadowWeight, lightMask);
#endif
#if defined(KATSA_USER_UNSHADED)
    vec3 result = texel.rgb + maps.emission;
#else
    vec3 result = texel.rgb * diffuseLight * (surfacePbr && !unlit ? 1.0 - maps.metalness : 1.0)
        + specularLight + maps.emission;
    if (!unlit) {
        result = applyToneMapping(result);
        // lightInfluence below 1 blends toward the flat (unlit) colour; fog fades with it.
        result = mix(result, texel.rgb + maps.emission, lightDetach);
    }
#endif
    // Shadow view (debug.shadowView): red = shadowed, green = lit, blue = shadow data not
    // evaluated; brightness shows the sun cascade (brightest = nearest, darkest = farthest).
    if (shadowDebug && !unlit) {
        result = (debugVisibility > 1.5
                ? vec3(0.1, 0.15, 0.6)
                : mix(vec3(1.0, 0.05, 0.05), vec3(0.1, 0.9, 0.2), debugVisibility))
                * (debugCascade > 0 ? 1.15 - 0.3 * float(debugCascade) : 1.0)
            + result * 0.0001;
    }
    // Normal view (debug.normalView): world normal as colour, to spot flipped skinned normals.
    if (normalDebug && !unlit) {
        result = normal * 0.5 + 0.5 + result * 0.0001;
    }
    if (unlit) {
        return vec4(result, texel.a);
    }
    return vec4(applyFog(result, cameraDistance, lightDetach), texel.a);
}
#endif
