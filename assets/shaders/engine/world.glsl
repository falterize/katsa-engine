#pragma language glsl3
varying highp vec3 worldPosition;
varying highp vec3 worldNormal;
varying highp vec3 diagnosticPosition;
uniform bool surfaceMissing;
uniform highp vec4 surfaceDiagnosticBounds;
flat varying highp vec2 relevantLights;
#ifdef VERTEX
uniform bool skinEnabled;
uniform highp mat4 skinBones[32];
attribute highp vec4 skinJoints;
attribute highp vec4 skinWeights;
uniform bool skinExtended;

// Vertex-only matrices avoid cross-stage precision/layout mismatches on GLES drivers.
uniform highp mat4 model;
uniform highp mat4 viewProjection;
uniform highp mat3 objectNormalMatrix;
attribute highp vec3 vertexNormal;
attribute highp vec4 instanceRow1;
attribute highp vec4 instanceRow2;
attribute highp vec4 instanceRow3;
attribute highp vec4 instanceRow4;
attribute highp vec3 instanceNormal1;
attribute highp vec3 instanceNormal2;
attribute highp vec3 instanceNormal3;
uniform bool instanced;
uniform highp vec2 objectLights1;
attribute highp vec2 instanceLights1;
uniform highp float materialTime;
// @include assets/shaders/engine/meshTransform.glsl
// MATERIAL_VERTEX_DECLARATIONS
vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    relevantLights=instanced ? instanceLights1 : objectLights1;
    highp mat4 modelMatrix=meshModelMatrix();
    highp mat3 normalMatrix=objectNormalMatrix;
    if(instanced) {
        normalMatrix=transpose(mat3(instanceNormal1,instanceNormal2,instanceNormal3));
    }
    // Skinned meshes derive the normal matrix from the model matrix sent with the same draw,
    // so it can never lag behind a stale per-object uniform.
    else if(skinEnabled) normalMatrix=transpose(inverse(mat3(modelMatrix)));
    diagnosticPosition = surfaceMissing
        ? (vertexPosition.xyz-surfaceDiagnosticBounds.xyz)*surfaceDiagnosticBounds.w
        : vec3(0.0);
    highp vec4 localPosition = vertexPosition;
    highp vec3 localNormal = vertexNormal;

    if(skinEnabled) {
        highp mat4 deform=meshSkinMatrix();
        localPosition=deform*localPosition;
        localNormal=transpose(inverse(mat3(deform)))*localNormal;
    }
    // MATERIAL_VERTEX
    highp vec4 world = modelMatrix * localPosition;
    worldPosition = world.xyz;
    worldNormal = normalMatrix * localNormal;
    return viewProjection * world;
}
#endif
#ifdef PIXEL
// EARLY_DEPTH_BEGIN
uniform bool depthPrepassEnabled;
uniform highp Image depthPrepassTexture;
uniform highp vec2 depthPrepassSize;
const highp float depthPrepassGuard=2.0/16777215.0;
// EARLY_DEPTH_END
uniform highp vec4 lightPosition[32];
uniform highp vec4 lightDirection[32];
uniform highp vec4 lightColor[32];
uniform highp vec4 lightExtra[32];
uniform int lightCount;
uniform bool objectLightMaskEnabled;
uniform vec3 ambient;
uniform float brightness;
uniform bool toneMapping;
uniform bool shadowDebug;
uniform bool normalDebug;
uniform float exposure;
uniform highp vec3 cameraPosition;
uniform vec4 fogColor;
uniform highp vec4 fogSettings;
uniform float time;
uniform bool unlit;
// 1 - lightInfluence: 0 = fully lit (also when never sent), 1 = flat colour.
uniform float lightDetach;
uniform bool canvasTexture;
uniform vec4 tint;
uniform float alphaCutoff;
uniform highp float materialTime;
// @include assets/shaders/engine/shadowSampling.glsl
uniform bool systemFogEnabled;
uniform bool systemToneMappingEnabled;
uniform bool decalTexture;
uniform bool decalRepeat;
uniform vec2 decalUVScale;
uniform vec2 decalUVOffset;
uniform float decalUVRotation;
uniform bool surfaceEnabled;
uniform bool surfaceOpaque;
uniform bool surfacePackedMR;
uniform bool hasNormalMap;
uniform bool hasRoughnessMap;
uniform bool hasMetalnessMap;
uniform bool hasOcclusionMap;
uniform bool hasEmissionMap;
uniform Image surfaceNormalMap;
uniform Image surfaceRoughnessMap;
uniform Image surfaceMetalnessMap;
uniform Image surfaceOcclusionMap;
uniform Image surfaceEmissionMap;
uniform vec3 surfaceColor;
uniform vec4 surfaceFactors;
uniform vec4 surfaceEmission;
// GGX/Schlick avoids per-light variable-power Phong while retaining material highlights.
vec4 materialSpecularTerms(vec3 normal,vec3 viewDirection,float roughness) {
    float nv=max(dot(normal,viewDirection),.001);
    float a=max(.04,roughness*roughness),a2=a*a;
    float k=(roughness+1.0)*(roughness+1.0)*.125;
    return vec4(a2,k,nv/(nv*(1.0-k)+k),4.0*nv);
}
vec3 preparedMaterialSpecular(vec3 normal,vec3 direction,vec3 viewDirection,vec3 f0,vec4 terms) {
    vec3 halfVector=normalize(direction+viewDirection);
    float nh=max(dot(normal,halfVector),0.0),nl=max(dot(normal,direction),0.0);
    float denominator=nh*nh*(terms.x-1.0)+1.0;
    float distribution=terms.x/max(3.14159265*denominator*denominator,.00001);
    float visibility=terms.z*(nl/(nl*(1.0-terms.y)+terms.y));
    float u=1.0-max(dot(viewDirection,halfVector),0.0),u2=u*u;
    vec3 fresnel=f0+(vec3(1.0)-f0)*(u2*u2*u);
    return fresnel*distribution*visibility/terms.w;
}
// Retain the helper signature for authored material hooks.
vec3 materialSpecular(vec3 normal,vec3 direction,vec3 viewDirection,vec3 f0,float roughness) {
    return preparedMaterialSpecular(normal,direction,viewDirection,f0,materialSpecularTerms(normal,viewDirection,roughness));
}
// MATERIAL_PIXEL_DECLARATIONS
uniform vec2 imageUVScale;
uniform vec2 imageUVOffset;
vec4 effect(vec4 color, Image textureImage, vec2 uv, vec2 screenPosition) {
    // EARLY_DEPTH_BEGIN
    if(depthPrepassEnabled && gl_FragCoord.z>Texel(depthPrepassTexture,screenPosition/depthPrepassSize).r+depthPrepassGuard)discard;
    // EARLY_DEPTH_END

    uv=uv*imageUVScale+imageUVOffset;
    if(decalTexture) {
        vec2 p=uv-.5;
        float c=cos(decalUVRotation),s=sin(decalUVRotation);
        uv=(mat2(c,-s,s,c)*p+.5)*decalUVScale+decalUVOffset;
        if(decalRepeat) uv=fract(uv);
        else if(any(lessThan(uv,vec2(0.))) || any(greaterThan(uv,vec2(1.)))) discard;
    }
    vec4 texel=Texel(textureImage,uv);
    if(canvasTexture && texel.a>0.0) texel.rgb/=texel.a;
    if(surfaceEnabled) {texel.rgb*=surfaceColor;if(surfaceOpaque)texel.a=1.0;}
    texel*=tint*color;
    if (texel.a<=alphaCutoff) discard;
    // Diagnostic material remains recognizable even when the mesh has no authored UVs.
    if(surfaceMissing) {
        float cell=mod(dot(floor(diagnosticPosition),vec3(1.0)),2.0);
        return vec4(mix(vec3(0.0),vec3(0.7,0.0,0.9),cell),texel.a);
    }
    highp vec3 normal=normalize(worldNormal);
    if (!gl_FrontFacing) normal=-normal;
    float roughness=1.0,metalness=0.0,occlusion=1.0;
    vec3 emission=vec3(0.0),f0=vec3(.04),specular=vec3(0.0);
    vec3 viewDirection=normalize(cameraPosition-worldPosition);
    if(surfaceEnabled) {
        roughness=clamp(surfaceFactors.x*(hasRoughnessMap ? (surfacePackedMR ? Texel(surfaceRoughnessMap,uv).g : Texel(surfaceRoughnessMap,uv).r) : 1.0),.04,1.0);
        metalness=clamp(surfaceFactors.y*(hasMetalnessMap ? (surfacePackedMR ? Texel(surfaceMetalnessMap,uv).b : Texel(surfaceMetalnessMap,uv).r) : 1.0),0.0,1.0);
        if(hasOcclusionMap)occlusion=mix(1.0,Texel(surfaceOcclusionMap,uv).r,surfaceFactors.w);
        emission=(hasEmissionMap ? Texel(surfaceEmissionMap,uv).rgb : vec3(1.0))*surfaceEmission.rgb*surfaceEmission.a;
        f0=mix(vec3(.04),texel.rgb,metalness);
        if(hasNormalMap) {
            vec3 a=dFdx(worldPosition),b=dFdy(worldPosition);
            vec2 u=dFdx(uv),v=dFdy(uv);
            float determinant=u.x*v.y-u.y*v.x;
            // UV derivatives shrink with a large UV area or a near camera, so the degeneracy test
            // must be relative to their size. An absolute threshold switched the normal map off
            // along a line of constant depth on big floors.
            float derivativeArea=length(u)*length(v);
            if(derivativeArea>0.0 && abs(determinant)>.0001*derivativeArea) {
                vec3 tangent=normalize((a*v.y-b*u.y)/determinant);
                tangent=normalize(tangent-normal*dot(tangent,normal));
                vec3 bitangent=normalize(cross(normal,tangent))*sign(determinant);
                vec3 mapped=Texel(surfaceNormalMap,uv).rgb*2.0-1.0;
                mapped.xy*=surfaceFactors.z;
                normal=normalize(mat3(tangent,bitangent,normal)*mapped);
            }
        }
    }
    vec4 specularTerms=materialSpecularTerms(normal,viewDirection,roughness);
    highp float cameraDistance=length(worldPosition-cameraPosition);
    highp float fadeWidth=max(shadowFadeDistance,0.001);
    float shadowWeight=1.0-smoothstep(max(0.0,shadowDistance-fadeWidth),shadowDistance,cameraDistance);
    vec3 lighting=unlit ? vec3(1.0) : ambient*occlusion;
    float debugVisibility=2.0;
    uint lightMask=uint(relevantLights.x) | (uint(relevantLights.y)<<16u);
    for(int i=0;i<32;i++) {
        if(unlit || i>=lightCount) break;
        if(objectLightMaskEnabled && (lightMask & (1u<<uint(i)))==0u) continue;
        if(lightExtra[i].y>1.5) {
            vec3 toward=-lightDirection[i].xyz;
            // Both diffuse and GGX contributions are zero on the unlit hemisphere.
            if(dot(normal,toward)<=0.0) continue;
            float visibility=1.0;
            if(receiveShadow && shadowWeight>0.0 && lightShadowData[i].x>=0.0) {
                visibility=mix(1.0,directionalVisibility(i,normal,toward),shadowWeight*shadowLightFade[i]);
                debugVisibility=min(debugVisibility,visibility);
            }
            if(surfaceEnabled)specular+=lightColor[i].rgb*lightColor[i].w*visibility*preparedMaterialSpecular(normal,toward,viewDirection,f0,specularTerms);
            lighting+=lightColor[i].rgb*lightColor[i].w*max(0.0,dot(normal,toward))*visibility;
            continue;
        }
        highp vec3 delta=(lightPosition[i].xyz-worldPosition)/max(lightPosition[i].w,0.001);
        if(dot(delta,delta)>1.0 || dot(normal,delta)<=0.0) continue;
        highp float distanceToLight=length(delta);
        highp vec3 toward=delta/max(distanceToLight,0.00001);
        float cone=1.0;
        if(lightExtra[i].y<0.5) cone=smoothstep(lightDirection[i].w,lightExtra[i].x,dot(-toward,lightDirection[i].xyz));
        if(cone<=0.0) continue;
        highp float falloff=max(0.0,1.0-distanceToLight);
        if(lightExtra[i].y>0.5) falloff=max(0.0,1.0-max(distanceToLight-lightExtra[i].x,0.0)/max(1.0-lightExtra[i].x,0.001));
        vec3 sampledLightColor=lightColor[i].rgb;
        if(lightExtra[i].z>0.5) sampledLightColor*=0.5+0.5*sin(vec3(time*0.8)+vec3(0.0,2.094395,4.18879));
        float visibility = 1.0;
        if(receiveShadow && shadowWeight>0.0 && lightShadowData[i].x >= 0.0) {
            int side = lightShadowData[i].y > 0.5 ? pointShadowFace(worldPosition-shadowLightPosition[i].xyz) : 0;
            int face = int(lightShadowData[i].x)+side;
            if((int(lightShadowData[i].z) & (1 << side)) != 0) {
                visibility = mix(1.0,shadowVisibility(face, localShadowProjection(i,side,normal), normal, toward, false, 0),shadowWeight*shadowLightFade[i]);
                debugVisibility=min(debugVisibility,visibility);
            }
        }
        if(surfaceEnabled)specular+=sampledLightColor*visibility*lightColor[i].w*cone*falloff*falloff*preparedMaterialSpecular(normal,toward,viewDirection,f0,specularTerms);
        lighting+=sampledLightColor*visibility*(lightColor[i].w*max(0.0,dot(normal,toward))*cone*falloff*falloff);
    }
    vec3 result=(texel.rgb*lighting*(surfaceEnabled && !unlit ? 1.0-metalness : 1.0)+specular)*(unlit ? 1.0 : max(brightness,0.0))+emission;
    if(!unlit && toneMapping && systemToneMappingEnabled) result = result * exposure / (vec3(1.0) + result * exposure);
    // lightInfluence below 1 blends toward the flat (unlit) colour; fog fades out with it as well.
    if(!unlit) result = mix(result, texel.rgb+emission, lightDetach);
    // Shadow view (debug.shadowView): red = shadowed, green = lit, blue = shadow data not evaluated;
    // brightness shows the sun cascade (brightest = nearest, darkest = farthest).
    if(shadowDebug && !unlit) result=(debugVisibility>1.5 ? vec3(0.1,0.15,0.6) : mix(vec3(1.0,0.05,0.05),vec3(0.1,0.9,0.2),debugVisibility))*(debugCascade>0 ? 1.15-0.3*float(debugCascade) : 1.0)+result*0.0001;
    // Normal view (debug.normalView): world normal as colour, to spot flipped skinned normals.
    if(normalDebug && !unlit) result=normal*0.5+0.5+result*0.0001;
    // MATERIAL_PIXEL
    if(unlit || !systemFogEnabled) return vec4(result,texel.a);
    highp float distanceToCamera=cameraDistance;
    highp float d=max(0.0,distanceToCamera-fogSettings.y);
    highp float fog=1.0-exp(-max(fogSettings.x,0.0)*d);
    if(fogSettings.w>0.5) fog=d/max(fogSettings.z-fogSettings.y,0.001);
    fog=clamp(fog,0.0,fogColor.a)*(1.0-lightDetach);
    return vec4(mix(result,fogColor.rgb,fog),texel.a);
}
#endif
