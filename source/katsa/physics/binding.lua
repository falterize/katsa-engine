-- FFI declarations and lazy loader for the katsa_box2d native library, plus shared scratch buffers.
local ffi = require('ffi')
local Native = require('source.katsa.core.native')

ffi.cdef([[
typedef void (*kb2_contact_cb)(intptr_t user, void* contact);
typedef void (*kb2_post_cb)(intptr_t user, void* contact, const float* impulses, int count);
typedef int (*kb2_filter_cb)(intptr_t user, void* a, void* b);
typedef int (*kb2_query_cb)(void* fixture);
typedef float (*kb2_ray_cb)(void* fixture, float x, float y, float nx, float ny, float fraction);
void* kb2_world_new(float gx, float gy, intptr_t user);
void kb2_world_free(void* w);
void kb2_world_step(void* w, float dt, int vi, int pi);
void kb2_world_set_gravity(void* w, float x, float y);
void kb2_world_get_gravity(void* w, float* out);
void kb2_world_set_callbacks(void* w, kb2_contact_cb b, kb2_contact_cb e, kb2_contact_cb p, kb2_post_cb s);
void kb2_world_set_filter(void* w, kb2_filter_cb f);
int kb2_world_is_locked(void* w);
void kb2_world_set_sleeping_allowed(void* w, int v);
int kb2_world_get_sleeping_allowed(void* w);
int kb2_world_contact_count(void* w);
int kb2_world_contacts(void* w, void** out, int max);
void kb2_world_shift_origin(void* w, float x, float y);
void kb2_world_query(void* w, float lx, float ly, float ux, float uy, kb2_query_cb cb);
void kb2_world_raycast(void* w, float x1, float y1, float x2, float y2, kb2_ray_cb cb);
void* kb2_world_ground(void* w);
void* kb2_body_new(void* w, int type, float x, float y, float angle);
void kb2_body_destroy(void* w, void* b);
void kb2_body_set_userid(void* b, intptr_t id);
intptr_t kb2_body_get_userid(void* b);
void kb2_body_get_position(void* b, float* o);
float kb2_body_get_angle(void* b);
void kb2_body_set_transform(void* b, float x, float y, float a);
void kb2_body_get_linear_velocity(void* b, float* o);
void kb2_body_set_linear_velocity(void* b, float x, float y);
float kb2_body_get_angular_velocity(void* b);
void kb2_body_set_angular_velocity(void* b, float v);
void kb2_body_apply_force(void* b, float fx, float fy, float px, float py, int point);
void kb2_body_apply_impulse(void* b, float ix, float iy, float px, float py, int point);
void kb2_body_apply_torque(void* b, float t);
void kb2_body_apply_angular_impulse(void* b, float i);
float kb2_body_get_mass(void* b);
float kb2_body_get_inertia(void* b);
void kb2_body_get_mass_data(void* b, float* o);
void kb2_body_set_mass_data(void* b, float cx, float cy, float m, float i);
void kb2_body_reset_mass(void* b);
void kb2_body_get_world_center(void* b, float* o);
void kb2_body_get_local_center(void* b, float* o);
void kb2_body_world_point(void* b, float x, float y, float* o);
void kb2_body_world_vector(void* b, float x, float y, float* o);
void kb2_body_local_point(void* b, float x, float y, float* o);
void kb2_body_local_vector(void* b, float x, float y, float* o);
void kb2_body_velocity_at(void* b, float x, float y, float* o, int local);
float kb2_body_get_linear_damping(void* b);
void kb2_body_set_linear_damping(void* b, float v);
float kb2_body_get_angular_damping(void* b);
void kb2_body_set_angular_damping(void* b, float v);
float kb2_body_get_gravity_scale(void* b);
void kb2_body_set_gravity_scale(void* b, float v);
int kb2_body_get_type(void* b);
void kb2_body_set_type(void* b, int t);
int kb2_body_get_flag(void* b, int flag);
void kb2_body_set_flag(void* b, int flag, int v);
int kb2_body_fixtures(void* b, void** out, int max);
int kb2_body_contacts(void* b, void** out, int max);
int kb2_body_joints(void* b, void** out, int max);
void* kb2_shape_circle(float x, float y, float r);
void* kb2_shape_polygon(const float* pts, int n);
void* kb2_shape_box(float hx, float hy, float cx, float cy, float angle);
void* kb2_shape_edge(float x1, float y1, float x2, float y2);
void* kb2_shape_chain(const float* pts, int n, int loop);
void kb2_shape_free(void* s);
int kb2_shape_type(void* s);
float kb2_shape_radius(void* s);
void kb2_shape_set_radius(void* s, float r);
int kb2_shape_child_count(void* s);
int kb2_shape_points(void* s, float* out, int max);
int kb2_shape_test_point(void* s, float x, float y, float angle, float px, float py);
int kb2_shape_raycast(void* s, float x1, float y1, float x2, float y2, float maxFraction, float x, float y, float angle, int child, float* out);
void kb2_shape_aabb(void* s, float x, float y, float angle, int child, float* out);
void kb2_shape_mass(void* s, float density, float* out);
float kb2_distance(void* a, int ia, float ax, float ay, float aangle, void* b, int ib, float bx, float by, float bangle);
void* kb2_fixture_new(void* body, void* shape, float density);
void kb2_fixture_destroy(void* body, void* f);
void kb2_fixture_set_userid(void* f, intptr_t id);
intptr_t kb2_fixture_get_userid(void* f);
void* kb2_fixture_body(void* f);
void* kb2_fixture_shape(void* f);
float kb2_fixture_get(void* f, int what);
void kb2_fixture_set(void* f, int what, float v);
void kb2_fixture_get_filter(void* f, int* out);
void kb2_fixture_set_filter(void* f, int cat, int mask, int group);
int kb2_fixture_test_point(void* f, float x, float y);
int kb2_fixture_raycast(void* f, float x1, float y1, float x2, float y2, float maxFraction, int child, float* out);
void kb2_fixture_aabb(void* f, int child, float* out);
void kb2_fixture_mass(void* f, float* out);
void kb2_contact_fixtures(void* c, void** out);
int kb2_contact_world_manifold(void* c, float* out);
int kb2_contact_is_touching(void* c);
int kb2_contact_is_enabled(void* c);
void kb2_contact_set_enabled(void* c, int v);
float kb2_contact_get(void* c, int what);
void kb2_contact_set(void* c, int what, float v);
void kb2_contact_reset(void* c, int what);
void* kb2_joint_revolute(void* w, void* a, void* b, float xa, float ya, float xb, float yb, int collide, float ref);
void* kb2_joint_prismatic(void* w, void* a, void* b, float xa, float ya, float xb, float yb, float ax, float ay, int collide, float ref);
void* kb2_joint_weld(void* w, void* a, void* b, float xa, float ya, float xb, float yb, int collide, float ref);
void* kb2_joint_rope(void* w, void* a, void* b, float xa, float ya, float xb, float yb, float maxLength, int collide);
void* kb2_joint_distance(void* w, void* a, void* b, float xa, float ya, float xb, float yb, int collide);
void* kb2_joint_wheel(void* w, void* a, void* b, float xa, float ya, float xb, float yb, float ax, float ay, int collide);
void* kb2_joint_friction(void* w, void* a, void* b, float xa, float ya, float xb, float yb, int collide);
void* kb2_joint_motor(void* w, void* a, void* b, float correction, int collide);
void* kb2_joint_pulley(void* w, void* a, void* b, float gax, float gay, float gbx, float gby, float xa, float ya, float xb, float yb, float ratio, int collide);
void* kb2_joint_gear(void* w, void* j1, void* j2, float ratio, int collide);
void* kb2_joint_mouse(void* w, void* body, float x, float y, float maxForce);
void kb2_joint_destroy(void* w, void* j);
void kb2_joint_set_userid(void* j, intptr_t id);
int kb2_joint_type(void* j);
void kb2_joint_bodies(void* j, void** out);
void kb2_joint_anchors(void* j, float* o);
void kb2_joint_reaction(void* j, float inv_dt, float* o);
int kb2_joint_collide(void* j);
float kb2_joint_get(void* j, int what);
void kb2_joint_set(void* j, int what, float v);
void kb2_joint_set_limits(void* j, float lower, float upper);
void kb2_joint_set_vec(void* j, int what, float x, float y);
void kb2_joint_get_vec(void* j, int what, float* o);
]])

local Binding = {
    pair = ffi.new('float[2]'),
    quad = ffi.new('float[4]'),
    six = ffi.new('float[6]'),
}

local library

function Binding.lib()
    if not library then
        library = assert(Native.load('Box2D'))
    end
    return library
end

return Binding
