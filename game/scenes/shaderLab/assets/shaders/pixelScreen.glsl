shader_type canvas_item;

// Mosaic: every block of pixelSize x pixelSize screen pixels shows one colour.
uniform float pixelSize : hint_range(1.0, 64.0) = 8.0;

void fragment() {
    float block = max(1.0, pixelSize);
    vec2 localPixel = UV * CANVAS_SIZE - REGION_ORIGIN;
    vec2 center = (floor(localPixel / block) + 0.5) * block;
    center = clamp(center, vec2(0.5), max(vec2(0.5), REGION_SIZE - vec2(0.5)));
    COLOR = Texel(TEXTURE, (REGION_ORIGIN + center) / CANVAS_SIZE) * VERTEX_COLOR;
}
