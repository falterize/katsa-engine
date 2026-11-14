shader_type spatial;

#include "./common.glsl"

uniform float amplitude : hint_range(0.0, 2.0) = 0.25;
uniform vec3 glow : source_color = vec3(1.0, 0.5, 0.25);
varying float height;

void vertex() {
    VERTEX.y += ripple(VERTEX.x, TIME) * amplitude;
    height = VERTEX.y;
}

void fragment() {
    ALBEDO = mix(ALBEDO, glow, clamp(height, 0.0, 1.0));
    ROUGHNESS = 0.4;
}
