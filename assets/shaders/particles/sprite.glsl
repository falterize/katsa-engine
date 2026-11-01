#pragma language glsl3
varying highp vec3 particleWorldPosition;
#ifdef VERTEX
uniform mat4 viewProjection;
uniform highp float materialTime;
// MATERIAL_VERTEX_DECLARATIONS
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec4 localPosition=vertex_position;
    // MATERIAL_VERTEX
    particleWorldPosition=localPosition.xyz;
    return viewProjection * localPosition;
}
#endif
#ifdef PIXEL
uniform bool multiplyMode;
// Shadow lookups read this copy: it is nudged toward the light so a particle never compares
// its own depth with the billboard its emitter casts into the atlas (self-shadow flicker).
highp vec3 particleShadowPosition;
uniform highp float particleShadowOffset;
#define worldPosition particleShadowPosition
// @include assets/shaders/engine/shadowSampling.glsl
uniform highp vec3 cameraPosition;
uniform float particleShadowSlot[8];
uniform vec3 particleLighting;
uniform bool particleUnlit;
uniform float particleBrightness;
uniform float particleWorldBrightness;
uniform vec3 particleFacing;
uniform int particleLightCount;
uniform vec4 particleLightPosition[8];
uniform vec4 particleLightColor[8];
uniform vec4 particleLightDirection[8];
uniform highp float materialTime;
// MATERIAL_PIXEL_DECLARATIONS
vec4 effect(vec4 color, Image spriteImage, vec2 uv, vec2 screen_coords) {
    vec4 texel = Texel(spriteImage, uv) * color;
    vec3 light=particleLighting;
    if(!particleUnlit) {
        for(int i=0;i<8;i++) {
            if(i>=particleLightCount) break;
            if(particleLightPosition[i].w==0.0) {
                vec3 direction=-particleLightDirection[i].xyz;
                int slot=int(particleShadowSlot[i]);
                particleShadowPosition=particleWorldPosition+direction*particleShadowOffset;
                float visibility=receiveShadow && slot>=0 && lightShadowData[slot].x>=0.0
                    ? directionalVisibility(slot,particleFacing,direction) : 1.0;
                light+=visibility*particleLightColor[i].rgb*particleLightColor[i].a*abs(dot(particleFacing,direction));
                continue;
            }
            vec3 delta=particleLightPosition[i].xyz-particleWorldPosition;
            float distance=length(delta), radius=max(.001,particleLightPosition[i].w);
            if(distance>=radius) continue;
            vec3 direction=delta/max(.001,distance);
            float cone=particleLightDirection[i].w < -1.0 ? 1.0 : smoothstep(particleLightDirection[i].w, min(.999,particleLightDirection[i].w+.1),dot(-direction,particleLightDirection[i].xyz));
            float attenuation=1.0-distance/radius;
            float visibility=1.0;
            int slot=int(particleShadowSlot[i]);
            particleShadowPosition=particleWorldPosition+direction*particleShadowOffset;
            if(receiveShadow && slot>=0 && lightShadowData[slot].x>=0.0) {
                int side=lightShadowData[slot].y>.5 ? pointShadowFace(worldPosition-shadowLightPosition[slot].xyz) : 0;
                if((int(lightShadowData[slot].z)&(1<<side))!=0)
                    visibility=shadowVisibility(int(lightShadowData[slot].x)+side,localShadowProjection(slot,side,particleFacing),particleFacing,direction,false,0);
            }
            light+=visibility*particleLightColor[i].rgb*particleLightColor[i].a*attenuation*attenuation*cone*abs(dot(particleFacing,direction));
        }
        light*=particleWorldBrightness;
    }
    vec3 result=texel.rgb*light*particleBrightness;
    // MATERIAL_PIXEL
    if (multiplyMode) return vec4(mix(vec3(1.0), result, texel.a), 1.0);
    return vec4(result,texel.a);
}
#endif
