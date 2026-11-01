#pragma language glsl3
#ifdef VERTEX
uniform highp mat4 model;
uniform highp mat4 viewProjection;
uniform bool instanced;
uniform bool skinEnabled;
uniform highp mat4 skinBones[32];
attribute highp vec4 skinJoints;
attribute highp vec4 skinWeights;
uniform bool skinExtended;
attribute highp vec4 instanceRow1;
attribute highp vec4 instanceRow2;
attribute highp vec4 instanceRow3;
attribute highp vec4 instanceRow4;
// @include assets/shaders/engine/meshTransform.glsl
vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    highp vec4 localPosition=vertexPosition;
    if(skinEnabled) localPosition=meshSkinMatrix()*localPosition;
    highp vec4 world=meshModelMatrix()*localPosition;
    return viewProjection*world;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) { return vec4(1.0); }
#endif
