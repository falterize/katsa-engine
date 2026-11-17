shader_type spatial;

// Block material. The mesher packs two things the plain vertex format has no room for:
//   * the normal's LENGTH is the ambient-occlusion shade of the corner (its direction is the
//     face direction), so the interpolated value darkens creases smoothly;
//   * u and v hold tile * 32 + 8 + repeat, where the tile is the atlas column/row and the repeat
//     counts blocks across a merged rectangle. The fragment picks the tile and repeats it.
varying vec2 packedUV;
varying float shade;

void vertex() {
    packedUV = UV;
    shade = length(NORMAL);
    NORMAL = NORMAL / shade;
}

void fragment() {
    vec2 tile = floor(packedUV / 32.0);
    vec2 inside = clamp(fract(packedUV - tile * 32.0 - 8.0), 0.002, 0.998);
    ALBEDO = texture(TEXTURE, (tile + inside) * 0.25).rgb * MODULATE.rgb * shade;
}
