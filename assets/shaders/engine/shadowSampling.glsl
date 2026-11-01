uniform highp Image shadowMatrixData;
uniform highp vec2 shadowAtlasSize;
uniform highp vec4 lightShadowData[32];
uniform highp vec4 shadowLightPosition[32];
uniform float shadowLightFade[32];
uniform highp vec4 shadowLightDirection[32];
uniform highp Image shadowAtlas;
uniform highp vec4 shadowParameters;
uniform highp vec4 shadowSoftness;
uniform highp float directionalShadowDepthScale;
uniform highp vec3 directionalShadowTexelDepth;
uniform highp float shadowNear;
uniform highp float shadowFaceResolution;
uniform highp vec2 shadowTexelSize;
uniform bool receiveShadow;
uniform highp float shadowDistance;
uniform highp float shadowFadeDistance;
highp mat4 shadowMatrix(int face) {
    highp float y = (float(face) + 0.5) / 192.0;
    return transpose(mat4(Texel(shadowMatrixData, vec2(0.125, y)),
        Texel(shadowMatrixData, vec2(0.375, y)), Texel(shadowMatrixData, vec2(0.625, y)),
        Texel(shadowMatrixData, vec2(0.875, y))));
}
// Local projections use their published source snapshot, saving four matrix
// texture reads per shadowed fragment. Sun cascades retain snapped matrices.
highp vec4 localShadowProjection(int light, int side, vec3 normal) {
    highp vec3 forward = shadowLightDirection[light].xyz;
    highp vec3 right, up;
    if(lightShadowData[light].y > 0.5) {
        // Cubemap axes are constant. Preserve the vertical-face epsilon basis
        // without normalizing or crossing vectors for each receiving fragment.
        if(side < 2) {
            float sign = side == 0 ? 1.0 : -1.0;
            forward = vec3(sign, 0.0, 0.0);
            right = vec3(0.0, 0.0, -sign);
            up = vec3(0.0, 1.0, 0.0);
        } else if(side < 4) {
            float sign = side == 2 ? 1.0 : -1.0;
            forward = vec3(0.0, sign, 0.0);
            right = vec3(0.0, 0.0, 1.0);
            up = vec3(sign, 0.0, 0.0);
        } else {
            float sign = side == 4 ? 1.0 : -1.0;
            forward = vec3(0.0, 0.0, sign);
            right = vec3(sign, 0.0, 0.0);
            up = vec3(0.0, 1.0, 0.0);
        }
    } else {
        right = normalize(vec3(forward.z, 0.0, -forward.x + (abs(forward.y) > .99 ? .00001 : 0.0)));
        up = cross(forward, right);
    }
    highp vec3 relative=worldPosition+normal*shadowParameters.y-shadowLightPosition[light].xyz;
    highp float nearPlane=shadowLightDirection[light].w;
    highp float farPlane=shadowLightPosition[light].w;
    highp float depth=dot(forward,relative);
    highp float extent=lightShadowData[light].w;
    return vec4(dot(right,relative)/extent,-dot(up,relative)/extent,
        (farPlane+nearPlane)/(farPlane-nearPlane)*depth-2.0*farPlane*nearPlane/(farPlane-nearPlane),depth);
}
float shadowVisibility(int face, highp vec4 p, vec3 normal, vec3 towardLight, bool directional, int cascade) {
    highp vec3 ndc = p.xyz / p.w;
    if(p.w <= 0.0 || any(greaterThan(abs(ndc), vec3(1.0)))) return 1.0;
    highp vec2 tile = vec2(float(face % int(shadowAtlasSize.x)), float(face / int(shadowAtlasSize.x)));
    highp vec2 uv = ((ndc.xy * 0.5 + 0.5) + tile) / shadowAtlasSize;
    // All sources use the same world-unit bias and slope/texel correction.
    // Projection converts that displacement into comparable depth units.
    highp float cosine = clamp(dot(normal, towardLight), 0.0, 1.0);
    highp float slope = sqrt(max(0.0, 1.0 - cosine * cosine)) / max(cosine, 0.1);
    highp float distance = max(p.w, shadowNear);
    highp float depthScale = directional ? directionalShadowDepthScale : shadowNear / (distance * distance);
    highp float texelDepth = directional ? directionalShadowTexelDepth[cascade]
        : 4.0 * shadowNear / (distance * shadowFaceResolution);
    highp float bias = shadowParameters.x * depthScale + texelDepth * slope;
    highp float depth = ndc.z * 0.5 + 0.5 - bias;
    float visibility = 0.0;
    int samples = int(shadowParameters.w);
    float radius=1.0;
    if(shadowSoftness.x>0.5) {
        float blockers=0.0,blockerDepth=0.0;
        for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
            vec2 inset=shadowTexelSize*.5;
            vec2 q=clamp(uv+vec2(float(x),float(y))*shadowTexelSize*shadowSoftness.w,
                tile/shadowAtlasSize+inset,(tile+1.0)/shadowAtlasSize-inset);
            float d=Texel(shadowAtlas,q).r;
            if(d<depth){blockers+=1.0;blockerDepth+=d;}
        }
        if(blockers<.5)return 1.0;
        blockerDepth/=blockers;
        radius=clamp((depth-blockerDepth)/max(blockerDepth,.001)*shadowSoftness.y*shadowFaceResolution,.5,shadowSoftness.z);
        samples=9;
    }
    if(samples == 1) visibility = step(depth, Texel(shadowAtlas, uv).r);
    else {
        int side = samples == 4 ? 2 : 3;
        for(int y=0; y<3; y++) for(int x=0; x<3; x++) {
            if(x>=side || y>=side) continue;
            vec2 offset = (vec2(float(x),float(y)) - float(side-1)*0.5) * shadowTexelSize * radius;
            vec2 inset = shadowTexelSize * 0.5;
            vec2 sampleUV = clamp(uv + offset, tile / shadowAtlasSize + inset, (tile+1.0)/shadowAtlasSize - inset);
            visibility += step(depth, Texel(shadowAtlas, sampleUV).r);
        }
        visibility /= float(samples);
    }
    return mix(1.0, visibility, shadowParameters.z);
}
float directionalVisibility(int light, vec3 normal, vec3 towardLight) {
    int base = int(lightShadowData[light].x);
    for(int cascade=0; cascade<3; cascade++) {
        highp vec4 p = shadowMatrix(base + cascade) * vec4(worldPosition + normal * shadowParameters.y, 1.0);
        highp vec3 ndc = p.xyz / p.w;
        highp float edge = max(abs(ndc.x), abs(ndc.y));
        if(edge <= 1.0 && abs(ndc.z) <= 1.0) {
            float visibility = shadowVisibility(base + cascade, p, normal, towardLight, true, cascade);
            if(cascade < 2 && edge > 0.8) {
                float nextVisibility = shadowVisibility(base + cascade + 1, shadowMatrix(base + cascade+1)*vec4(worldPosition+normal*shadowParameters.y,1.0), normal, towardLight, true, cascade + 1);
                visibility = mix(visibility, nextVisibility, smoothstep(0.8, 1.0, edge));
            }
            return visibility;
        }
    }
    return 1.0;
}
int pointShadowFace(vec3 delta) {
    vec3 a = abs(delta);
    if(a.x>=a.y && a.x>=a.z) return delta.x>=0.0 ? 0 : 1;
    if(a.y>=a.z) return delta.y>=0.0 ? 2 : 3;
    return delta.z>=0.0 ? 4 : 5;
}
