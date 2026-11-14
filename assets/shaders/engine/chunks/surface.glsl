// Surface appearance: UV transforms, decals and the PBR texture maps. Pixel stage only.
//
// Every `#specialize` flag is a uniform in the general program and a constant in variants for
// objects that never use the feature, so the GPU compiler drops the unused branch.
uniform vec2 imageUVScale;
uniform vec2 imageUVOffset;
#specialize bool decalTexture
uniform bool decalRepeat;
uniform vec2 decalUVScale;
uniform vec2 decalUVOffset;
uniform float decalUVRotation;
#specialize bool surfaceEnabled
uniform bool surfaceOpaque;
uniform bool surfacePackedMR;
#specialize bool hasNormalMap
#specialize bool hasRoughnessMap
#specialize bool hasMetalnessMap
#specialize bool hasOcclusionMap
#specialize bool hasEmissionMap
uniform Image surfaceNormalMap;
uniform Image surfaceRoughnessMap;
uniform Image surfaceMetalnessMap;
uniform Image surfaceOcclusionMap;
uniform Image surfaceEmissionMap;
uniform vec3 surfaceColor;
// x roughness, y metalness, z normal map strength, w occlusion strength.
uniform vec4 surfaceFactors;
uniform vec4 surfaceEmission;

// Decals rotate and scale the UVs about the centre; non repeating decals discard outside [0, 1].
vec2 decalUV(vec2 uv) {
    if (decalTexture) {
        vec2 p = uv - .5;
        float c = cos(decalUVRotation), s = sin(decalUVRotation);
        uv = (mat2(c, -s, s, c) * p + .5) * decalUVScale + decalUVOffset;
        if (decalRepeat) {
            uv = fract(uv);
        } else if (any(lessThan(uv, vec2(0.))) || any(greaterThan(uv, vec2(1.)))) {
            discard;
        }
    }
    return uv;
}

struct SurfaceMaps {
    highp vec3 normal;
    float roughness;
    float metalness;
    float occlusion;
    vec3 emission;
    vec3 f0;
};

// Samples the maps for one fragment. Without a surface appearance the material is a rough
// dielectric with no emission, which is what plain textured meshes use.
SurfaceMaps sampleSurfaceMaps(vec2 uv, vec3 albedo, highp vec3 normal) {
    SurfaceMaps maps;
    maps.normal = normal;
    maps.roughness = 1.0;
    maps.metalness = 0.0;
    maps.occlusion = 1.0;
    maps.emission = vec3(0.0);
    maps.f0 = vec3(.04);
    if (!surfaceEnabled) {
        return maps;
    }
    maps.roughness = clamp(
        surfaceFactors.x
            * (hasRoughnessMap
                    ? (surfacePackedMR ? Texel(surfaceRoughnessMap, uv).g : Texel(surfaceRoughnessMap, uv).r)
                    : 1.0),
        .04,
        1.0
    );
    maps.metalness = clamp(
        surfaceFactors.y
            * (hasMetalnessMap
                    ? (surfacePackedMR ? Texel(surfaceMetalnessMap, uv).b : Texel(surfaceMetalnessMap, uv).r)
                    : 1.0),
        0.0,
        1.0
    );
    if (hasOcclusionMap) {
        maps.occlusion = mix(1.0, Texel(surfaceOcclusionMap, uv).r, surfaceFactors.w);
    }
    maps.emission = (hasEmissionMap ? Texel(surfaceEmissionMap, uv).rgb : vec3(1.0))
        * surfaceEmission.rgb * surfaceEmission.a;
    maps.f0 = mix(vec3(.04), albedo, maps.metalness);
    if (hasNormalMap) {
        // The tangent frame comes from screen space derivatives, so meshes need no tangents.
        vec3 a = dFdx(worldPosition), b = dFdy(worldPosition);
        vec2 u = dFdx(uv), v = dFdy(uv);
        float determinant = u.x * v.y - u.y * v.x;
        // UV derivatives shrink with a large UV area or a near camera, so the degeneracy test
        // must be relative to their size. An absolute threshold switched the normal map off
        // along a line of constant depth on big floors.
        float derivativeArea = length(u) * length(v);
        if (derivativeArea > 0.0 && abs(determinant) > .0001 * derivativeArea) {
            vec3 tangent = normalize((a * v.y - b * u.y) / determinant);
            tangent = normalize(tangent - normal * dot(tangent, normal));
            vec3 bitangent = normalize(cross(normal, tangent)) * sign(determinant);
            vec3 mapped = Texel(surfaceNormalMap, uv).rgb * 2.0 - 1.0;
            mapped.xy *= surfaceFactors.z;
            maps.normal = normalize(mat3(tangent, bitangent, normal) * mapped);
        }
    }
    return maps;
}
