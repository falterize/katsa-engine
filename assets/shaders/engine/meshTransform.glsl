highp mat4 meshModelMatrix() {
    if(instanced) return transpose(mat4(instanceRow1,instanceRow2,instanceRow3,instanceRow4));
    return model;
}
highp mat4 meshSkinMatrix() {
    highp mat4 result = skinWeights.x*skinBones[int(skinJoints.x)]
        +skinWeights.y*skinBones[int(skinJoints.y)]
        +skinWeights.z*skinBones[int(skinJoints.z)]
        +skinWeights.w*skinBones[int(skinJoints.w)];
    if(skinExtended) result += instanceRow2.x*skinBones[int(instanceRow1.x)]
        +instanceRow2.y*skinBones[int(instanceRow1.y)]
        +instanceRow2.z*skinBones[int(instanceRow1.z)]
        +instanceRow2.w*skinBones[int(instanceRow1.w)];
    return result;
}
