// Shared by the sky background and the user sky shader: where a view ray lands in the sky image.
//
// Two layouts: a 4x3 cube cross (one cell per face) and an equirectangular panorama. The ray of
// each pixel comes from the camera basis (right/up/forward, already rotated by the sky yaw).
// Texture coordinates are inset by half a texel so filtering never reads across face borders.
// Pixel stage only.
uniform highp vec3 right;
uniform highp vec3 up;
uniform highp vec3 forward;
uniform highp vec2 viewSize;
uniform highp float focal;
uniform highp vec2 edgeInset;
uniform bool panorama;
uniform highp vec4 tint;

highp vec2 panoramaUV(highp vec3 ray) {
    highp vec3 d = normalize(ray);
    highp vec2 uv = vec2(
        fract(.5 + atan(d.x, d.z) / 6.28318530718),
        .5 - asin(clamp(d.y, -1., 1.)) / 3.14159265359
    );
    return clamp(uv, edgeInset, vec2(1.) - edgeInset);
}

// The cross layout is four cells wide and three tall:      [+Y]
// the cell is the face the ray exits through and p is the  [-X][+Z][+X][-Z]
// position on that face in -1..1.                           [-Y]
highp vec2 crossUV(highp vec3 ray) {
    highp vec3 a = abs(ray);
    highp vec2 cell;
    highp vec2 p;
    if (a.x >= a.y && a.x >= a.z) {
        if (ray.x > 0.) {
            cell = vec2(2., 1.);
            p = vec2(-ray.z, -ray.y) / a.x;
        } else {
            cell = vec2(0., 1.);
            p = vec2(ray.z, -ray.y) / a.x;
        }
    } else if (a.y >= a.z) {
        if (ray.y > 0.) {
            cell = vec2(1., 0.);
            p = vec2(ray.x, ray.z) / a.y;
        } else {
            cell = vec2(1., 2.);
            p = vec2(ray.x, -ray.z) / a.y;
        }
    } else {
        if (ray.z > 0.) {
            cell = vec2(1., 1.);
            p = vec2(ray.x, -ray.y) / a.z;
        } else {
            cell = vec2(3., 1.);
            p = vec2(-ray.x, -ray.y) / a.z;
        }
    }
    p = clamp(p * .5 + .5, edgeInset, vec2(1.) - edgeInset);
    return (cell + p) / vec2(4., 3.);
}

highp vec3 skyRay(vec2 uv) {
    return right * ((uv.x - .5) * viewSize.x / focal) + up * ((.5 - uv.y) * viewSize.y / focal)
        + forward;
}

vec3 skyColor(Image image, highp vec3 ray) {
    highp vec2 sampleUV = panorama ? panoramaUV(ray) : crossUV(ray);
    return Texel(image, sampleUV).rgb * tint.rgb * tint.a;
}
