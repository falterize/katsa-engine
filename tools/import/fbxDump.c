/* Dumps the triangulated, world-space geometry of an FBX as JSON, grouped by node and material.
 *   fbxDump model.fbx > model.json
 * Built with ufbx (https://github.com/ufbx/ufbx, public domain / MIT): gcc fbxDump.c ufbx.c -lm */
#include "ufbx.h"
#include <stdio.h>
#include <stdlib.h>

static void floats(const char *key, const float *v, size_t n) {
    printf("\"%s\":[", key);
    for (size_t i = 0; i < n; i++) printf(i ? ",%.6g" : "%.6g", v[i]);
    printf("]");
}

int main(int argc, char **argv) {
    ufbx_load_opts opts = { 0 };
    opts.target_axes = ufbx_axes_right_handed_y_up;
    opts.target_unit_meters = 1.0f;
    opts.space_conversion = UFBX_SPACE_CONVERSION_TRANSFORM_ROOT;
    ufbx_error err;
    ufbx_scene *scene = ufbx_load_file(argv[1], &opts, &err);
    if (!scene) { fprintf(stderr, "load failed: %s\n", err.description.data); return 1; }
    printf("{\"nodes\":[\n");
    int first = 1;
    for (size_t i = 0; i < scene->nodes.count; i++) {
        ufbx_node *node = scene->nodes.data[i];
        ufbx_mesh *mesh = node->mesh;
        if (!mesh) continue;
        ufbx_matrix g = node->geometry_to_world;
        ufbx_matrix gn = ufbx_matrix_for_normals(&g);
        for (size_t m = 0; m < (mesh->materials.count ? mesh->materials.count : 1); m++) {
            size_t cap = mesh->num_triangles * 3 + 3;
            float *p = malloc(cap * 3 * sizeof(float)), *nr = malloc(cap * 3 * sizeof(float)), *uv = malloc(cap * 2 * sizeof(float));
            size_t count = 0;
            uint32_t tri[64 * 3];
            for (size_t f = 0; f < mesh->num_faces; f++) {
                ufbx_face face = mesh->faces.data[f];
                if (mesh->face_material.count && mesh->face_material.data[f] != m) continue;
                if (face.num_indices > 64) continue;
                size_t nt = ufbx_triangulate_face(tri, 64 * 3, mesh, face);
                for (size_t k = 0; k < nt * 3; k++) {
                    uint32_t idx = tri[k];
                    ufbx_vec3 pos = ufbx_transform_position(&g, ufbx_get_vertex_vec3(&mesh->vertex_position, idx));
                    ufbx_vec3 nor = mesh->vertex_normal.exists ? ufbx_transform_direction(&gn, ufbx_get_vertex_vec3(&mesh->vertex_normal, idx)) : (ufbx_vec3){ 0, 1, 0 };
                    double l = sqrt(nor.x * nor.x + nor.y * nor.y + nor.z * nor.z);
                    if (l > 1e-9) { nor.x /= l; nor.y /= l; nor.z /= l; }
                    ufbx_vec2 t = mesh->vertex_uv.exists ? ufbx_get_vertex_vec2(&mesh->vertex_uv, idx) : (ufbx_vec2){ 0, 0 };
                    p[count * 3] = pos.x; p[count * 3 + 1] = pos.y; p[count * 3 + 2] = pos.z;
                    nr[count * 3] = nor.x; nr[count * 3 + 1] = nor.y; nr[count * 3 + 2] = nor.z;
                    uv[count * 2] = t.x; uv[count * 2 + 1] = t.y;
                    count++;
                }
            }
            if (count == 0) { free(p); free(nr); free(uv); continue; }
            ufbx_material *mat = mesh->materials.count ? mesh->materials.data[m] : NULL;
            printf("%s{\"name\":\"%s\",\"material\":\"%s\",\"count\":%zu,", first ? "" : ",\n", node->name.data, mat ? mat->name.data : "", count);
            floats("p", p, count * 3); printf(","); floats("n", nr, count * 3); printf(","); floats("uv", uv, count * 2);
            printf("}");
            first = 0;
            free(p); free(nr); free(uv);
        }
    }
    printf("\n]}\n");
    return 0;
}
