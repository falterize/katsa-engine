shader_type canvas_item;

// CRT static: horizontal jitter, noise and scanlines over the node's region.
uniform float noiseStrength : hint_range(0.0, 1.0) = 0.35;
uniform float scanlineStrength : hint_range(0.0, 1.0) = 0.35;
uniform float distortion : hint_range(0.0, 0.2) = 0.02;

highp float hash(highp vec2 p) {
    // Bound the input before arithmetic; mediump sine hashes overflow at phone resolutions.
    highp vec3 q = fract(vec3(mod(p, 289.0).xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

void fragment() {
    highp vec2 localUV = REGION_UV;
    highp float tick = mod(floor(TIME * 24.0), 4096.0);
    highp float jitter = (hash(vec2(floor(localUV.y * REGION_SIZE.y / 3.0), tick)) - 0.5) * distortion;
    localUV.x = clamp(localUV.x + jitter, 0.0, 1.0);
    highp vec2 sampleUV = (REGION_ORIGIN + localUV * REGION_SIZE) / CANVAS_SIZE;
    vec4 source = Texel(TEXTURE, sampleUV) * VERTEX_COLOR;
    highp float noise = hash(floor(localUV * REGION_SIZE / 2.0) + tick);
    highp float scan = 0.5 + 0.5 * cos(mod(localUV.y * REGION_SIZE.y, 2.0) * 3.14159265);
    source.rgb = mix(source.rgb, vec3(noise) * source.a, clamp(noiseStrength, 0.0, 1.0));
    source.rgb *= 1.0 - clamp(scanlineStrength, 0.0, 1.0) * scan;
    COLOR = source;
}
