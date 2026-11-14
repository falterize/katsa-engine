shader_type spatial;

uniform float shift = 0.0;

void vertex() {
    VERTEX.x += shift;
}
