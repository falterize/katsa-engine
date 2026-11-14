#pragma language glsl3
// Shadow depth pass for meshes. Draws casters into the shadow atlas tile `atlasTile`.
//
// User vertex() code runs here too, so displaced geometry casts the shadow it shows. In this
// pass VIEW_MATRIX and PROJECTION_MATRIX are identity and POSITION is ignored: the light's
// projection is applied after vertex(). Flag KATSA_SHADOW_OPAQUE drops the alpha test.
varying float casterAlpha;
uniform highp float time;
uniform highp vec2 viewportSize;
uniform highp vec3 cameraPosition;

#user_code

#ifdef STAGE_VERTEX
#include "./chunks/mesh.glsl"
uniform highp mat4 viewProjection;
uniform highp vec4 atlasTile;
attribute highp vec3 vertexNormal;

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    highp vec4 localPosition = vertexPosition;
    highp vec3 localNormal = vertexNormal;
    highp mat4 MODEL_MATRIX = meshModelMatrix();
    if (skinEnabled) {
        highp mat4 deform = meshSkinMatrix();
        localPosition = deform * localPosition;
        localNormal = transpose(inverse(mat3(deform))) * localNormal;
    }
    // VertexColor, not VaryingColor: the constant draw colour must not scale the caster alpha.
    vec4 COLOR = VertexColor;
#ifdef KATSA_USER_VERTEX
    highp vec3 VERTEX = localPosition.xyz;
    highp vec3 NORMAL = localNormal;
    vec2 UV = VaryingTexCoord.st;
    highp mat4 VIEW_MATRIX = mat4(1.0);
    highp mat4 PROJECTION_MATRIX = mat4(1.0);
    highp mat4 MODELVIEW_MATRIX = MODEL_MATRIX;
    highp float TIME = time;
    highp vec2 VIEWPORT_SIZE = viewportSize;
    highp vec3 CAMERA_POSITION = cameraPosition;
    highp vec4 POSITION = vec4(0.0);
    KATSA_USER_VERTEX;
    localPosition.xyz = VERTEX;
    VaryingTexCoord.st = UV;
#endif
    casterAlpha = COLOR.a;
    highp vec4 clip = viewProjection * MODEL_MATRIX * localPosition;
    clip.xy = clip.xy * atlasTile.xy + clip.w * atlasTile.zw;
    return clip;
}
#endif

#ifdef STAGE_PIXEL
uniform float alphaCutoff;
uniform bool particleCaster;
uniform float opacity;
uniform bool surfaceOpaque;
uniform vec2 imageUVScale;
uniform vec2 imageUVOffset;

vec4 effect(vec4 color, Image textureImage, vec2 uv, vec2 screenPosition) {
#ifndef KATSA_SHADOW_OPAQUE
    uv = uv * imageUVScale + imageUVOffset;
    float alpha = (surfaceOpaque ? 1.0 : Texel(textureImage, uv).a) * opacity
        * (particleCaster ? casterAlpha : 1.0);
    if (alpha <= alphaCutoff) {
        discard;
    }
#endif
    return vec4(1.0);
}
#endif
