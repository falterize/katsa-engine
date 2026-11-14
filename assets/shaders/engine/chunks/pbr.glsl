// GGX/Schlick specular. Pixel stage only; pure functions, safe to call from user shaders.
//
// materialSpecularTerms() computes the view dependent part once per fragment so each light only
// pays for the half-vector terms; materialSpecular() wraps both for code that has one light.
vec4 materialSpecularTerms(vec3 normal, vec3 viewDirection, float roughness) {
    float nv = max(dot(normal, viewDirection), .001);
    float a = max(.04, roughness * roughness), a2 = a * a;
    float k = (roughness + 1.0) * (roughness + 1.0) * .125;
    return vec4(a2, k, nv / (nv * (1.0 - k) + k), 4.0 * nv);
}

vec3 preparedMaterialSpecular(
    vec3 normal,
    vec3 direction,
    vec3 viewDirection,
    vec3 f0,
    vec4 terms
) {
    vec3 halfVector = normalize(direction + viewDirection);
    float nh = max(dot(normal, halfVector), 0.0), nl = max(dot(normal, direction), 0.0);
    float denominator = nh * nh * (terms.x - 1.0) + 1.0;
    float distribution = terms.x / max(3.14159265 * denominator * denominator, .00001);
    float visibility = terms.z * (nl / (nl * (1.0 - terms.y) + terms.y));
    float u = 1.0 - max(dot(viewDirection, halfVector), 0.0), u2 = u * u;
    vec3 fresnel = f0 + (vec3(1.0) - f0) * (u2 * u2 * u);
    return fresnel * distribution * visibility / terms.w;
}

vec3 materialSpecular(
    vec3 normal,
    vec3 direction,
    vec3 viewDirection,
    vec3 f0,
    float roughness
) {
    return preparedMaterialSpecular(
        normal,
        direction,
        viewDirection,
        f0,
        materialSpecularTerms(normal, viewDirection, roughness)
    );
}
