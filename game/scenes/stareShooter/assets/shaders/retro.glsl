shader_type canvas_item;

// Retro screen: low-resolution sampling, jitter, chromatic offset, colour banding, vignette
// and grain. Port of a Godot screen shader. Disabled by default, as in main.tscn.
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    vec2 screenUV = UV;
    vec2 pixel = 1.0 / vec2(320.0, 240.0);
    vec2 uv = floor(screenUV / pixel) * pixel + pixel * 0.5;
    float t = floor(TIME * 1.2 * 8.0) / 8.0;
    float horizontal = (hash(vec2(floor(uv.y * 180.0), t)) - 0.5) * 0.008 * 0.75;
    float vertical = (hash(vec2(floor(uv.x * 180.0 * 0.4), t)) - 0.5) * 0.008 * 0.35;
    float micro = (hash(uv * 600.0 + t) - 0.5) * 0.008 * 0.1;
    uv += vec2(horizontal + micro, vertical + micro);
    vec2 offset = (uv - 0.5) * 0.015;
    vec3 result = vec3(
        Texel(TEXTURE, uv + offset).r,
        Texel(TEXTURE, uv).g,
        Texel(TEXTURE, uv - offset).b
    );
    result = floor(result * 16.0) / 16.0;
    result *= 1.0 - 0.8 * smoothstep(0.45, 0.9, distance(screenUV, vec2(0.5)));
    result += (hash(screenUV * 80.0 + floor(TIME * 50.0)) - 0.5) * 0.03;
    COLOR = vec4(result, 1.0) * VERTEX_COLOR;
}
