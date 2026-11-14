shader_type spatial;

// PlayStation style rendering: vertices snap to a coarse screen grid and textures are mapped
// affinely (no perspective correction), which makes surfaces wobble as the camera moves.
uniform float snapScale : hint_range(10.0, 400.0) = 75.0;

// uv * w and w interpolate perspective-correctly; their quotient in fragment() is the
// screen-linear (affine) interpolation of uv.
varying vec2 affineUV;
varying float affineW;

void vertex() {
    vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    vec2 snapped = floor(snapScale * clip.xy / clip.w) / snapScale;
    POSITION = vec4(snapped * clip.w, clip.z, clip.w);
    affineUV = UV * clip.w;
    affineW = clip.w;
}

void fragment() {
    ALBEDO = texture(TEXTURE, affineUV / affineW).rgb * MODULATE.rgb * COLOR.rgb;
}
