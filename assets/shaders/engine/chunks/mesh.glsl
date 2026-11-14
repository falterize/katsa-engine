// Mesh vertex inputs shared by every program that draws a Mesh3D: skinning and instancing.
// Vertex stage only. Declares the matrices and attributes; the helpers below combine them.
#specialize bool skinEnabled
#specialize bool skinExtended
uniform highp mat4 skinBones[32];
attribute highp vec4 skinJoints;
attribute highp vec4 skinWeights;

// Vertex-only matrices avoid cross-stage precision/layout mismatches on GLES drivers.
uniform highp mat4 model;
uniform bool instanced;
attribute highp vec4 instanceRow1;
attribute highp vec4 instanceRow2;
attribute highp vec4 instanceRow3;
attribute highp vec4 instanceRow4;

// Instances carry a transposed model matrix in four attributes; a lone mesh uses `model`.
highp mat4 meshModelMatrix() {
    if (instanced) {
        return transpose(mat4(instanceRow1, instanceRow2, instanceRow3, instanceRow4));
    }
    return model;
}

// Blend of up to four joints, or eight when `skinExtended` (the second four ride in the
// instance rows, which skinned meshes never use for instancing).
highp mat4 meshSkinMatrix() {
    highp mat4 result = skinWeights.x * skinBones[int(skinJoints.x)]
        + skinWeights.y * skinBones[int(skinJoints.y)]
        + skinWeights.z * skinBones[int(skinJoints.z)]
        + skinWeights.w * skinBones[int(skinJoints.w)];
    if (skinExtended) {
        result += instanceRow2.x * skinBones[int(instanceRow1.x)]
            + instanceRow2.y * skinBones[int(instanceRow1.y)]
            + instanceRow2.z * skinBones[int(instanceRow1.z)]
            + instanceRow2.w * skinBones[int(instanceRow1.w)];
    }
    return result;
}
