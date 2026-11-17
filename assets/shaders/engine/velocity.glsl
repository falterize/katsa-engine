#pragma language glsl3
// Velocity of one moving opaque mesh: where each pixel was last frame, as the difference of its
// screen position now and before, in uv units (current - previous). Skinned meshes move with their
// previous bone palette. Drawn on top of the camera velocity, depth-tested against the opaque
// scene depth, so a hidden part of a mesh writes nothing.
varying highp vec4 clipNow;
varying highp vec4 clipBefore;

#ifdef STAGE_VERTEX
#include "./chunks/mesh.glsl"
uniform highp mat4 viewProjection;
uniform highp mat4 previousViewProjection;
uniform highp mat4 previousModel;
uniform highp mat4 previousBones[32];

// The same blend as meshSkinMatrix(), with last frame's palette.
highp mat4 previousSkinMatrix() {
    highp mat4 result = skinWeights.x * previousBones[int(skinJoints.x)]
        + skinWeights.y * previousBones[int(skinJoints.y)]
        + skinWeights.z * previousBones[int(skinJoints.z)]
        + skinWeights.w * previousBones[int(skinJoints.w)];
    if (skinExtended) {
        result += instanceRow2.x * previousBones[int(instanceRow1.x)]
            + instanceRow2.y * previousBones[int(instanceRow1.y)]
            + instanceRow2.z * previousBones[int(instanceRow1.z)]
            + instanceRow2.w * previousBones[int(instanceRow1.w)];
    }
    return result;
}

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    highp vec4 now = vertexPosition;
    highp vec4 before = vertexPosition;
    if (skinEnabled) {
        now = meshSkinMatrix() * vertexPosition;
        before = previousSkinMatrix() * vertexPosition;
    }
    clipNow = viewProjection * meshModelMatrix() * now;
    clipBefore = previousViewProjection * previousModel * before;
    highp vec4 result = clipNow;
    // Pulls the mesh a hair towards the camera so it passes its own depth in the scene depth.
    result.z -= 0.0001 * result.w;
    return result;
}
#endif

#ifdef STAGE_PIXEL
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    if (clipBefore.w < 0.00001) {
        return vec4(0.0, 0.0, 1.0, 1.0);
    }
    highp vec2 now = clipNow.xy / clipNow.w;
    highp vec2 before = clipBefore.xy / clipBefore.w;
    return vec4((now - before) * 0.5, 1.0, 1.0);
}
#endif
