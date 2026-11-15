shader_type spatial;

// Samples the surface texture on a coarse grid of cells.
uniform vec2 pixelCells = vec2(8.0, 8.0);

void fragment() {
    vec2 cells = max(pixelCells, vec2(1.0));
    vec2 sampledUV = (floor(UV * cells) + 0.5) / cells;
    ALBEDO = texture(TEXTURE, sampledUV).rgb * MODULATE.rgb * COLOR.rgb;
}
