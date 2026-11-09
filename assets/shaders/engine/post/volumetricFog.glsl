// Volumetric fog: marches each pixel's view ray up to the scene depth, thinning the light by
// the fog it crosses and adding sunlight scattered toward the camera (shadowed by the sun's
// cascaded shadow map, which gives light shafts). Writes scatter colour in rgb and the light
// that still passes through in alpha; the apply shader composites it over the scene.
uniform highp Image depthTexture;
uniform highp vec2 viewSize;
uniform highp float focal;
uniform highp float pixelsPerUnit;
uniform highp vec2 depthRange;
uniform bool orthographic;
uniform highp vec3 cameraPosition;
uniform highp vec3 cameraRight;
uniform highp vec3 cameraUp;
uniform highp vec3 cameraForward;
uniform highp float density;
uniform highp float heightFalloff;
uniform highp float baseHeight;
uniform highp vec3 fogColor;
uniform highp float anisotropy;
uniform highp float ambientEnergy;
uniform highp float maxDistance;
uniform highp float skyAffect;
uniform int stepCount;
uniform bool sunEnabled;
uniform highp vec3 sunToward;     // unit vector from the scene toward the sun
uniform highp vec3 sunRadiance;   // sun colour times brightness
uniform int sunIndex;             // slot of the sun in the shadow tables (-1: no shadows)
uniform bool localShadows;        // point and spot lights also respect their shadow maps
uniform highp float localEnergy;
uniform bool lightClearing;       // Fog.lightClearing: lights thin the fog they shine through
uniform highp vec4 lightPosition[32];   // xyz position, w range
uniform highp vec4 lightDirection[32];  // xyz spot axis, w outer cone cosine
uniform highp vec4 lightColor[32];
uniform highp vec4 lightExtra[32];      // x inner cone / falloff start, y type (0 spot, 1 point, 2 sun)
uniform int lightCount;

highp vec3 worldPosition;
// @include assets/shaders/engine/shadowSampling.glsl

highp float viewDepth(highp vec2 uv) {
    highp float d=Texel(depthTexture,uv).r*2.0-1.0;
    if(orthographic) return (d-depthRange.y)/depthRange.x;
    return depthRange.y/(d-depthRange.x);
}
highp float noise(highp vec2 p) {
    return fract(52.9829189*fract(dot(p,vec2(.06711056,.00583715))));
}
highp float henyeyGreenstein(highp float cosine) {
    highp float g=anisotropy;
    return (1.0-g*g)/(12.566371*pow(max(1.0+g*g-2.0*g*cosine,1e-4),1.5));
}

// Light of one point or spot light that reaches `worldPosition`, scattered toward the camera.
// `reach` (0..1) is how strongly the light reaches this point; the fog thins by it (scaled by the
// light's own fogClearing).
highp vec3 localLight(int i,highp vec3 viewDirection,out highp float reach) {
    reach=0.0;
    highp vec3 delta=(lightPosition[i].xyz-worldPosition)/max(lightPosition[i].w,0.001);
    highp float distanceToLight=length(delta);
    if(distanceToLight>=1.0) return vec3(0.0);
    highp vec3 toward=delta/max(distanceToLight,0.00001);
    highp float cone=1.0;
    if(lightExtra[i].y<0.5) cone=smoothstep(lightDirection[i].w,lightExtra[i].x,dot(-toward,lightDirection[i].xyz));
    if(cone<=0.0) return vec3(0.0);
    highp float falloff=max(0.0,1.0-distanceToLight);
    if(lightExtra[i].y>0.5) falloff=max(0.0,1.0-max(distanceToLight-lightExtra[i].x,0.0)/max(1.0-lightExtra[i].x,0.001));
    highp float visibility=1.0;
    if(localShadows && lightShadowData[i].x>=0.0) {
        int side=lightShadowData[i].y>0.5 ? pointShadowFace(worldPosition-shadowLightPosition[i].xyz) : 0;
        if((int(lightShadowData[i].z) & (1<<side))!=0) {
            visibility=shadowVisibility(int(lightShadowData[i].x)+side,
                localShadowProjection(i,side,toward),toward,toward,false,0);
        }
    }
    reach=cone*falloff*falloff*visibility;
    return lightColor[i].rgb*lightColor[i].w*localEnergy*reach
        *henyeyGreenstein(dot(viewDirection,toward));
}

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    highp vec2 centered=vec2(uv.x-.5,.5-uv.y)*viewSize;
    highp vec3 viewRay;     // view-space direction with z = 1 (perspective) or the fixed axis
    highp vec3 origin=cameraPosition;
    highp vec3 direction;
    highp float length;
    highp float rawDepth=Texel(depthTexture,uv).r;
    bool sky=rawDepth>=.99999;
    if(orthographic) {
        direction=cameraForward;
        origin=cameraPosition+cameraRight*(centered.x/pixelsPerUnit)+cameraUp*(centered.y/pixelsPerUnit);
        length=sky ? maxDistance : viewDepth(uv);
    } else {
        highp vec3 v=vec3(centered/focal,1.0);
        direction=normalize(cameraRight*v.x+cameraUp*v.y+cameraForward*v.z);
        length=sky ? maxDistance : viewDepth(uv)*sqrt(dot(v,v));
    }
    length=min(length,maxDistance);
    highp float weight=sky ? skyAffect : 1.0;
    highp float stepLength=length/float(stepCount);
    highp float offset=noise(screen);
    highp float phase=sunEnabled ? henyeyGreenstein(dot(direction,sunToward)) : 0.0;
    highp float transmittance=1.0;
    highp vec3 scatter=vec3(0.0);
    for(int i=0;i<64;i++) {
        if(i>=stepCount) break;
        highp float t=(float(i)+offset)*stepLength;
        worldPosition=origin+direction*t;
        highp float dens=density*(heightFalloff>0.0 ?
            exp(-heightFalloff*max(0.0,worldPosition.y-baseHeight)) : 1.0);
        highp vec3 light=fogColor*ambientEnergy;
        if(sunEnabled) {
            highp float visibility=1.0;
            if(sunIndex>=0) visibility=directionalVisibility(sunIndex,vec3(0.0,1.0,0.0),sunToward);
            light+=fogColor*sunRadiance*visibility*phase;
        }
        highp float cleared=0.0;
        for(int i=0;i<32;i++) {
            if(i>=lightCount) break;
            if(lightExtra[i].y>1.5) continue;
            highp float reach;
            light+=fogColor*localLight(i,direction,reach);
            cleared=max(cleared,reach*lightExtra[i].w); // w: the light's own fogClearing
        }
        // Lights burn the fog away where they shine, like fog lamps: the beam stays readable.
        if(lightClearing) dens*=1.0-clamp(cleared,0.0,1.0);
        highp float extinction=dens*stepLength;
        highp float absorbed=1.0-exp(-extinction);
        scatter+=transmittance*absorbed*light;
        transmittance*=1.0-absorbed;
        if(transmittance<.01) break;
    }
    transmittance=mix(1.0,transmittance,weight);
    scatter*=weight;
    return vec4(scatter,transmittance);
}
