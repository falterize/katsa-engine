#pragma language glsl3
varying float casterAlpha;
#ifdef VERTEX
uniform bool skinEnabled;
uniform highp mat4 skinBones[32];
attribute highp vec4 skinJoints;
attribute highp vec4 skinWeights;
uniform bool skinExtended;

uniform highp mat4 model;
uniform highp mat4 viewProjection;
uniform highp vec4 atlasTile;
uniform highp float materialTime;
attribute highp vec3 vertexNormal;
attribute highp vec4 instanceRow1;
attribute highp vec4 instanceRow2;
attribute highp vec4 instanceRow3;
attribute highp vec4 instanceRow4;
uniform bool instanced;
// MATERIAL_VERTEX_DECLARATIONS
vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    casterAlpha=VertexColor.a;
    highp vec4 localPosition = vertexPosition;
    highp vec3 localNormal = vertexNormal;

    if(skinEnabled) {
        highp mat4 deform=skinWeights.x*skinBones[int(skinJoints.x)]
            +skinWeights.y*skinBones[int(skinJoints.y)]
            +skinWeights.z*skinBones[int(skinJoints.z)]
            +skinWeights.w*skinBones[int(skinJoints.w)];
        if(skinExtended) deform += instanceRow2.x*skinBones[int(instanceRow1.x)]
            +instanceRow2.y*skinBones[int(instanceRow1.y)]
            +instanceRow2.z*skinBones[int(instanceRow1.z)]
            +instanceRow2.w*skinBones[int(instanceRow1.w)];
        localPosition=deform*localPosition;
    }
    // MATERIAL_VERTEX
    highp mat4 modelMatrix = model;
    if(instanced) modelMatrix = transpose(mat4(instanceRow1, instanceRow2, instanceRow3, instanceRow4));
    highp vec4 clip = viewProjection * modelMatrix * localPosition;
    clip.xy = clip.xy * atlasTile.xy + clip.w * atlasTile.zw;
    return clip;
}
#endif
#ifdef PIXEL
uniform float alphaCutoff;
uniform bool particleCaster;
uniform float opacity;
uniform bool surfaceOpaque;
uniform vec2 imageUVScale;
uniform vec2 imageUVOffset;
vec4 effect(vec4 color, Image textureImage, vec2 uv, vec2 screenPosition) {
    uv=uv*imageUVScale+imageUVOffset;
    if ((surfaceOpaque ? 1.0 : Texel(textureImage, uv).a) * opacity * (particleCaster ? casterAlpha : 1.0) <= alphaCutoff) discard;
    return vec4(1.0);
}
#endif
