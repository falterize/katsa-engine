shader_type spatial;

// PlayStation style rendering: vertices snap to a coarse screen grid and textures are mapped
// affinely (no perspective correction), which makes surfaces wobble as the camera moves.
// Affine mapping is only convincing on small triangles: a large quad (a floor with four
// vertices) smears its texture, exactly like on the original hardware. Subdivide big surfaces
// or lower `affine` to blend back to perspective-correct mapping.
uniform float snapScale : hint_range(10.0, 400.0) = 75.0;
uniform float affine : hint_range(0.0, 1.0) = 1.0;

// uv * w and w interpolate perspective-correctly; their quotient in fragment() is the
// screen-linear (affine) interpolation of uv.
varying vec2 affineUV;
varying float affineW;

void vertex() {
    vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    // Vertices at or behind the camera plane have no stable screen position: leave them alone,
    // otherwise snapping a near-zero w throws them across the screen.
    if (clip.w > 0.05) {
        vec2 snapped = floor(snapScale * clip.xy / clip.w) / snapScale;
        clip.xy = snapped * clip.w;
    }
    POSITION = clip;
    affineUV = UV * clip.w;
    affineW = clip.w;
}

void fragment() {
    vec2 screenUV = affineUV / max(affineW, 0.0001);
    ALBEDO = texture(TEXTURE, mix(UV, screenUV, affine)).rgb * MODULATE.rgb * COLOR.rgb;
}
