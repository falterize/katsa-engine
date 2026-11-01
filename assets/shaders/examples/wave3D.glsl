// @vertexDeclarations
uniform float waveAmplitude;
// @vertexCode
localPosition.y += sin(materialTime * 2.0 + localPosition.x * 4.0) * waveAmplitude;
// @fragmentDeclarations
uniform vec3 glowColor;
// @fragmentCode
result = mix(result, glowColor, 0.25 + 0.2 * sin(materialTime * 2.0));
