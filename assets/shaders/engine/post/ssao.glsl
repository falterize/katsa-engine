// Screen-space ambient occlusion from the scene depth. Draws occlusion (1 = open) into a
// half-resolution target; the apply shader multiplies it into the image.
#include "../chunks/depth.glsl"
uniform highp vec2 depthSize;        // depth texture size in pixels
uniform highp vec2 viewSize;         // logical view size the focal length belongs to
uniform highp float focal;           // perspective focal length (view-size units)
uniform highp float pixelsPerUnit;   // orthographic scale
uniform highp float radius;
uniform highp float bias;
uniform int sampleCount;

highp vec3 viewPosition(highp vec2 uv, highp float z) {
    highp vec2 centered = vec2(uv.x - .5, .5 - uv.y) * viewSize;
    if (orthographic) {
        return vec3(centered / pixelsPerUnit, z);
    }
    return vec3(centered / focal * z, z);
}

highp vec2 viewToUV(highp vec3 p) {
    highp vec2 s;
    if (orthographic) {
        s = p.xy * pixelsPerUnit / viewSize;
    } else {
        s = p.xy * focal / (max(p.z, 1e-4) * viewSize);
    }
    return vec2(.5 + s.x, .5 - s.y);
}

vec4 effect(vec4 color, Image image, vec2 uv, vec2 screenPosition) {
    highp vec2 texel = 1.0 / depthSize;
    // Sky and far clip carry no occluders.
    if (isSkyDepth(uv)) {
        return vec4(1.0);
    }
    highp float z = viewDepth(uv);
    highp vec3 p = viewPosition(uv, z);

    // Face normal from the smaller of the two depth steps on each axis.
    highp vec3 px1 = viewPosition(uv + vec2(texel.x, 0.), viewDepth(uv + vec2(texel.x, 0.)));
    highp vec3 px0 = viewPosition(uv - vec2(texel.x, 0.), viewDepth(uv - vec2(texel.x, 0.)));
    highp vec3 py1 = viewPosition(uv + vec2(0., texel.y), viewDepth(uv + vec2(0., texel.y)));
    highp vec3 py0 = viewPosition(uv - vec2(0., texel.y), viewDepth(uv - vec2(0., texel.y)));
    highp vec3 dx = abs(px1.z - p.z) < abs(p.z - px0.z) ? px1 - p : p - px0;
    highp vec3 dy = abs(py1.z - p.z) < abs(p.z - py0.z) ? py1 - p : p - py0;
    highp vec3 n = normalize(cross(dy, dx));
    if (n.z > 0.0) {
        n = -n; // face the camera (view space looks down +z)
    }

    // Depth changes by this much from one pixel to the next on this surface. On a far, grazing
    // floor that is several world units per pixel, so a tap that lands a pixel or two away would
    // read the floor itself as an occluder (this drew bands). Every tap tolerates the surface
    // slope times its pixel distance from the centre.
    // Depth is stored in steps (24 bits): one step in view units is `stair`. A side whose change
    // is much larger than the other side's plus the stair is an edge (a box foot beside the
    // floor), not slope, so it is ignored; otherwise the larger side counts, since on far floors
    // the smaller side is often zero.
    highp float stair = orthographic
        ? 4.0 * 2.0 / 16777216.0 / abs(depthRange.x)
        : 4.0 * 2.0 / 16777216.0 * z * z / abs(depthRange.y);
    highp vec4 steps = abs(vec4(px1.z - p.z, p.z - px0.z, py1.z - p.z, p.z - py0.z));
    highp vec2 sx = vec2(min(steps.x, steps.y), max(steps.x, steps.y));
    highp vec2 sy = vec2(min(steps.z, steps.w), max(steps.z, steps.w));
    highp float slopeX = sx.y <= 2.0 * sx.x + stair ? sx.y : sx.x + stair;
    highp float slopeY = sy.y <= 2.0 * sy.x + stair ? sy.y : sy.x + stair;
    highp float slope = max(slopeX, slopeY);

    highp float angle = screenNoise(screenPosition) * 6.2831853;
    // Orient the taps into the hemisphere above the surface.
    highp vec3 t = normalize(abs(n.y) < .99 ? cross(n, vec3(0., 1., 0.)) : cross(n, vec3(1., 0., 0.)));
    highp vec3 b = cross(n, t);
    highp float occlusion = 0.0;
    for (int i = 0; i < 24; i++) {
        if (i >= sampleCount) {
            break;
        }
        highp float fi = (float(i) + .5) / float(sampleCount);
        highp float a = angle + float(i) * 2.3999632; // golden angle spreads the taps
        highp vec3 dir = vec3(cos(a) * sqrt(fi), sin(a) * sqrt(fi), sqrt(1.0 - fi));
        highp float scale = mix(.15, 1.0, fi * fi);
        highp vec3 q = p + (t * dir.x + b * dir.y + n * dir.z) * radius * scale;
        highp vec2 quv = viewToUV(q);
        if (quv.x < 0. || quv.x > 1. || quv.y < 0. || quv.y > 1.) {
            continue;
        }
        highp float sceneZ = viewDepth(quv);
        highp float range = smoothstep(0.0, 1.0, radius / max(abs(z - sceneZ), 1e-4));
        highp float tolerance = bias + slope * 2.0 * length((quv - uv) * depthSize) + q.z * 0.004;
        occlusion += (sceneZ <= q.z - tolerance ? 1.0 : 0.0) * range;
    }
    return vec4(vec3(1.0 - occlusion / float(sampleCount)), 1.0);
}
