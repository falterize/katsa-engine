#pragma language glsl3
#ifdef VERTEX
uniform highp mat4 model;
uniform highp mat4 viewProjection;
uniform highp vec2 viewportSize;
uniform bool skinEnabled;
uniform highp mat4 skinBones[32];
attribute highp vec4 skinJoints;
attribute highp vec4 skinWeights;
uniform bool skinExtended;
attribute highp vec4 skinJointsExtra;
attribute highp vec4 skinWeightsExtra;
attribute highp vec3 edgeEnd;
attribute highp vec4 edgeJoints;
attribute highp vec4 edgeWeights;
attribute highp vec4 edgeJointsExtra;
attribute highp vec4 edgeWeightsExtra;
attribute highp vec2 edgeCorner;
mat4 skin(vec4 joints, vec4 weights) {
    return weights.x*skinBones[int(joints.x)]+weights.y*skinBones[int(joints.y)]
        +weights.z*skinBones[int(joints.z)]+weights.w*skinBones[int(joints.w)];
}
vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    vec4 startPosition = vertexPosition;
    vec4 endPosition=vec4(edgeEnd,1.0);
    if(skinEnabled) {
        vertexPosition=skin(skinJoints,skinWeights)*vertexPosition;
        endPosition=skin(edgeJoints,edgeWeights)*endPosition;
        if(skinExtended) {
            vertexPosition+=skin(skinJointsExtra,skinWeightsExtra)*startPosition;
            endPosition+=skin(edgeJointsExtra,edgeWeightsExtra)*vec4(edgeEnd,1.0);
        }
    }
    vec4 a=viewProjection*model*vertexPosition;
    vec4 b=viewProjection*model*endPosition;
    float da=a.z+a.w, db=b.z+b.w;
    if(da<=0.0 && db<=0.0) return vec4(0.0,0.0,2.0,1.0);
    if(da<0.0) a=mix(a,b,da/(da-db));
    if(db<0.0) b=mix(b,a,db/(db-da));
    if(a.w<=0.0 || b.w<=0.0) return vec4(0.0,0.0,2.0,1.0);
    vec2 delta=(b.xy/b.w-a.xy/a.w)*viewportSize;
    float lengthSquared=dot(delta,delta);
    if(lengthSquared<0.000001) return vec4(0.0,0.0,2.0,1.0);
    vec2 perpendicular=vec2(-delta.y,delta.x)*inversesqrt(lengthSquared);
    vec4 p=mix(a,b,edgeCorner.x);
    p.xy+=perpendicular*edgeCorner.y*p.w/viewportSize;
    return p;
}
#endif
#ifdef PIXEL
uniform float opacity;
vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    return vec4(0.35,0.85,1.0,opacity);
}
#endif
