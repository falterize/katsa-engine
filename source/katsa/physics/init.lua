-- katsa.physics: LÖVE-style 2D physics over Box2D 2.3.1 (katsa_box2d). Lengths are given in pixels and
-- divided by the meter scale; forces scale with the meter, torques and inertia with its square.
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

local Physics = {}
local lib
local function B()
    if not lib then
        lib = assert(Native.load('Box2D'))
    end
    return lib
end

local meter = 30
function Physics.setMeter(value)
    assert(value >= 1 and value <= 1000, 'Physics error: invalid meter')
    meter = value
end
function Physics.getMeter() return meter end

local function up(v) return v * meter end
local function down(v) return v / meter end

-- Registries map Box2D user ids back to Lua objects.
local nextId = 1
local objects = setmetatable({}, { __mode = 'v' })
local strong = {}
local function register(object)
    local id = nextId
    nextId = nextId + 1
    objects[id] = object
    strong[id] = object
    return id
end
local function unregister(id)
    strong[id] = nil
    objects[id] = nil
end

local pair, quad, six = ffi.new('float[2]'), ffi.new('float[4]'), ffi.new('float[6]')
local pending

local function guard(fn)
    return function(...)
        local ok, a, b = pcall(fn, ...)
        if not ok then
            pending = pending or a
            return 0
        end
        return a, b
    end
end

-- Classes ---------------------------------------------------------------------------------------

local World, Body, Fixture, Shape, Contact, Joint = {}, {}, {}, {}, {}, {}
for _, class in ipairs({ World, Body, Fixture, Shape, Contact, Joint }) do
    class.__index = class
end

local function alive(self, name)
    if self._destroyed then
        error('Attempt to use destroyed ' .. name, 3)
    end
end

-- Shapes ------------------------------------------------------------------------------------------

local shapeNames = { [0] = 'circle', 'edge', 'polygon', 'chain' }

local function newShape(handle, owned)
    local self = setmetatable({ _h = handle }, Shape)
    if owned then
        self._h = ffi.gc(handle, B().kb2_shape_free)
    end
    return self
end

local function points(args)
    local list = args
    if type(args[1]) == 'table' then
        list = args[1]
    end
    local out = ffi.new('float[?]', math.max(#list, 2))
    for i = 1, #list do
        out[i - 1] = down(list[i])
    end
    return out, #list / 2
end

function Physics.newCircleShape(a, b, c)
    local x, y, r = 0, 0, a
    if c ~= nil then
        x, y, r = a, b, c
    end
    return newShape(B().kb2_shape_circle(down(x), down(y), down(r)), true)
end
function Physics.newRectangleShape(a, b, c, d, e)
    local x, y, w, h, angle = 0, 0, a, b, 0
    if c ~= nil then
        x, y, w, h, angle = a, b, c, d, e or 0
    end
    return newShape(B().kb2_shape_box(down(w) / 2, down(h) / 2, down(x), down(y), angle), true)
end
function Physics.newPolygonShape(...)
    local pts, n = points({ ... })
    local handle = B().kb2_shape_polygon(pts, n)
    if handle == nil then
        error('Physics error: polygon needs 3 to 8 vertices forming a valid convex hull', 2)
    end
    return newShape(handle, true)
end
function Physics.newEdgeShape(x1, y1, x2, y2)
    return newShape(B().kb2_shape_edge(down(x1), down(y1), down(x2), down(y2)), true)
end
function Physics.newChainShape(loop, ...)
    local pts, n = points({ ... })
    assert(n >= 2, 'Physics error: chain shapes need at least two vertices')
    return newShape(B().kb2_shape_chain(pts, n, loop and 1 or 0), true)
end

function Shape:getType() return shapeNames[B().kb2_shape_type(self._h)] end
function Shape:getRadius() return up(B().kb2_shape_radius(self._h)) end
function Shape:setRadius(r) B().kb2_shape_set_radius(self._h, down(r)) end
function Shape:getChildCount() return B().kb2_shape_child_count(self._h) end
function Shape:getPoints()
    local buffer = ffi.new('float[16]')
    local n = B().kb2_shape_points(self._h, buffer, 8)
    local out = {}
    for i = 0, n * 2 - 1 do
        out[#out + 1] = up(buffer[i])
    end
    return unpack(out)
end
function Shape:getPoint()
    local buffer = ffi.new('float[2]')
    B().kb2_shape_points(self._h, buffer, 1)
    return up(buffer[0]), up(buffer[1])
end
function Shape:getVertexCount()
    local buffer = ffi.new('float[16]')
    return B().kb2_shape_points(self._h, buffer, 8)
end
function Shape:getPoints2() return self:getPoints() end
function Shape:testPoint(x, y, angle, px, py)
    return B().kb2_shape_test_point(self._h, down(x), down(y), angle, down(px), down(py)) ~= 0
end
function Shape:rayCast(x1, y1, x2, y2, maxFraction, tx, ty, angle, child)
    if not B().kb2_shape_raycast(self._h, down(x1), down(y1), down(x2), down(y2), maxFraction, down(tx), down(ty), angle, (child or 1) - 1, six) then
        return nil
    end
    return six[0], six[1], six[2]
end
function Shape:computeAABB(x, y, angle, child)
    B().kb2_shape_aabb(self._h, down(x), down(y), angle, (child or 1) - 1, quad)
    return up(quad[0]), up(quad[1]), up(quad[2]), up(quad[3])
end
function Shape:computeMass(density)
    B().kb2_shape_mass(self._h, density, quad)
    return up(quad[0]), up(quad[1]), quad[2], up(up(quad[3]))
end
function Shape:release() self._h = nil return true end
function Shape:type() return 'Shape' end
function Shape:typeOf(name) return name == 'Shape' or name == 'Object' end

-- Fixtures -----------------------------------------------------------------------------------------

function Physics.newFixture(body, shape, density)
    alive(body, 'Body')
    local handle = B().kb2_fixture_new(body._h, shape._h, density or 1)
    local self = setmetatable({ _h = handle, _body = body }, Fixture)
    self._id = register(self)
    B().kb2_fixture_set_userid(handle, self._id)
    body._fixtures[self] = true
    return self
end

local fixtureProps = { friction = 0, restitution = 1, density = 2, sensor = 3 }
function Fixture:getBody() return self._body end
function Fixture:getShape()
    alive(self, 'Fixture')
    self._shape = self._shape or newShape(B().kb2_fixture_shape(self._h), false)
    return self._shape
end
function Fixture:getType() return self:getShape():getType() end
function Fixture:getFriction() return B().kb2_fixture_get(self._h, 0) end
function Fixture:setFriction(v) alive(self, 'Fixture') B().kb2_fixture_set(self._h, 0, v) end
function Fixture:getRestitution() return B().kb2_fixture_get(self._h, 1) end
function Fixture:setRestitution(v) B().kb2_fixture_set(self._h, 1, v) end
function Fixture:getDensity() return B().kb2_fixture_get(self._h, 2) end
function Fixture:setDensity(v) B().kb2_fixture_set(self._h, 2, v) end
function Fixture:isSensor() alive(self, 'Fixture') return B().kb2_fixture_get(self._h, 3) ~= 0 end
function Fixture:setSensor(v) B().kb2_fixture_set(self._h, 3, v and 1 or 0) end
function Fixture:getFilterData()
    local out = ffi.new('int[3]')
    B().kb2_fixture_get_filter(self._h, out)
    return out[0], out[1], out[2]
end
function Fixture:setFilterData(category, mask, group)
    B().kb2_fixture_set_filter(self._h, category, mask, group)
end
function Fixture:getCategory()
    local c, _ = self:getFilterData()
    local list = {}
    for i = 1, 16 do
        if bit.band(c, bit.lshift(1, i - 1)) ~= 0 then list[#list + 1] = i end
    end
    return unpack(list)
end
function Fixture:getGroupIndex() local _, _, g = self:getFilterData() return g end
function Fixture:setGroupIndex(g) local c, m = self:getFilterData() B().kb2_fixture_set_filter(self._h, c, m, g) end
function Fixture:setUserData(data) self._userdata = data end
function Fixture:getUserData() return self._userdata end
function Fixture:testPoint(x, y) return B().kb2_fixture_test_point(self._h, down(x), down(y)) ~= 0 end
function Fixture:rayCast(x1, y1, x2, y2, maxFraction, child)
    if B().kb2_fixture_raycast(self._h, down(x1), down(y1), down(x2), down(y2), maxFraction, (child or 1) - 1, six) == 0 then
        return nil
    end
    return six[0], six[1], six[2]
end
function Fixture:getBoundingBox(child)
    B().kb2_fixture_aabb(self._h, (child or 1) - 1, quad)
    return up(quad[0]), up(quad[1]), up(quad[2]), up(quad[3])
end
function Fixture:getMassData()
    B().kb2_fixture_mass(self._h, quad)
    return up(quad[0]), up(quad[1]), quad[2], up(up(quad[3]))
end
function Fixture:isDestroyed() return self._destroyed == true end
function Fixture:destroy()
    if self._destroyed then return false end
    B().kb2_fixture_destroy(self._body._h, self._h)
    self._destroyed = true
    self._body._fixtures[self] = nil
    unregister(self._id)
    return true
end
function Fixture:release() return self:destroy() end
function Fixture:type() return 'Fixture' end
function Fixture:typeOf(name) return name == 'Fixture' or name == 'Object' end

-- Bodies ------------------------------------------------------------------------------------------------

local typeCodes = { static = 0, dynamic = 1, kinematic = 2 }
local typeNames = { [0] = 'static', 'dynamic', 'kinematic' }

function Physics.newBody(world, x, y, kind)
    alive(world, 'World')
    kind = kind or 'static'
    assert(typeCodes[kind], 'Invalid body type: ' .. tostring(kind))
    local handle = B().kb2_body_new(world._h, typeCodes[kind], down(x or 0), down(y or 0), 0)
    local self = setmetatable({ _h = handle, _world = world, _fixtures = {}, _joints = {} }, Body)
    self._id = register(self)
    B().kb2_body_set_userid(handle, self._id)
    world._bodies[self] = true
    return self
end

local function body_vec(fn)
    return function(self, ...)
        alive(self, 'Body')
        fn(self._h, ...)
        return up(pair[0]), up(pair[1])
    end
end

function Body:getPosition() alive(self, 'Body') B().kb2_body_get_position(self._h, pair) return up(pair[0]), up(pair[1]) end
function Body:getX() alive(self, 'Body') B().kb2_body_get_position(self._h, pair) return up(pair[0]) end
function Body:getY() alive(self, 'Body') B().kb2_body_get_position(self._h, pair) return up(pair[1]) end
function Body:getAngle() alive(self, 'Body') return B().kb2_body_get_angle(self._h) end
function Body:getTransform()
    local x, y = self:getPosition()
    return x, y, self:getAngle()
end
function Body:setPosition(x, y) alive(self, 'Body') B().kb2_body_set_transform(self._h, down(x), down(y), B().kb2_body_get_angle(self._h)) end
function Body:setX(x) self:setPosition(x, self:getY()) end
function Body:setY(y) self:setPosition(self:getX(), y) end
function Body:setAngle(a) alive(self, 'Body') B().kb2_body_get_position(self._h, pair) B().kb2_body_set_transform(self._h, pair[0], pair[1], a) end
function Body:setTransform(x, y, a) alive(self, 'Body') B().kb2_body_set_transform(self._h, down(x), down(y), a or self:getAngle()) end
function Body:getLinearVelocity() alive(self, 'Body') B().kb2_body_get_linear_velocity(self._h, pair) return up(pair[0]), up(pair[1]) end
function Body:setLinearVelocity(x, y) alive(self, 'Body') B().kb2_body_set_linear_velocity(self._h, down(x), down(y)) end
function Body:getAngularVelocity() alive(self, 'Body') return B().kb2_body_get_angular_velocity(self._h) end
function Body:setAngularVelocity(v) alive(self, 'Body') B().kb2_body_set_angular_velocity(self._h, v) end
function Body:applyForce(fx, fy, px, py)
    alive(self, 'Body')
    B().kb2_body_apply_force(self._h, down(fx), down(fy), down(px or 0), down(py or 0), px and 1 or 0)
end
function Body:applyLinearImpulse(ix, iy, px, py)
    alive(self, 'Body')
    B().kb2_body_apply_impulse(self._h, down(ix), down(iy), down(px or 0), down(py or 0), px and 1 or 0)
end
function Body:applyTorque(t) alive(self, 'Body') B().kb2_body_apply_torque(self._h, down(down(t))) end
function Body:applyAngularImpulse(i) alive(self, 'Body') B().kb2_body_apply_angular_impulse(self._h, down(down(i))) end
function Body:getMass() alive(self, 'Body') return B().kb2_body_get_mass(self._h) end
function Body:getInertia() alive(self, 'Body') return up(up(B().kb2_body_get_inertia(self._h))) end
function Body:getMassData()
    alive(self, 'Body')
    B().kb2_body_get_mass_data(self._h, quad)
    return up(quad[0]), up(quad[1]), quad[2], up(up(quad[3]))
end
function Body:setMassData(x, y, mass, inertia)
    alive(self, 'Body')
    B().kb2_body_set_mass_data(self._h, down(x), down(y), mass, down(down(inertia)))
end
function Body:setMass(mass)
    local x, y, _, inertia = self:getMassData()
    self:setMassData(x, y, mass, inertia)
end
function Body:setInertia(inertia)
    local x, y, mass = self:getMassData()
    self:setMassData(x, y, mass, inertia)
end
function Body:resetMassData() alive(self, 'Body') B().kb2_body_reset_mass(self._h) end
function Body:getWorldCenter() alive(self, 'Body') B().kb2_body_get_world_center(self._h, pair) return up(pair[0]), up(pair[1]) end
function Body:getLocalCenter() alive(self, 'Body') B().kb2_body_get_local_center(self._h, pair) return up(pair[0]), up(pair[1]) end
function Body:getWorldPoint(x, y) alive(self, 'Body') B().kb2_body_world_point(self._h, down(x), down(y), pair) return up(pair[0]), up(pair[1]) end
function Body:getWorldVector(x, y) alive(self, 'Body') B().kb2_body_world_vector(self._h, down(x), down(y), pair) return up(pair[0]), up(pair[1]) end
function Body:getLocalPoint(x, y) alive(self, 'Body') B().kb2_body_local_point(self._h, down(x), down(y), pair) return up(pair[0]), up(pair[1]) end
function Body:getLocalVector(x, y) alive(self, 'Body') B().kb2_body_local_vector(self._h, down(x), down(y), pair) return up(pair[0]), up(pair[1]) end
function Body:getWorldPoints(...)
    local out, args = {}, { ... }
    for i = 1, #args - 1, 2 do
        local x, y = self:getWorldPoint(args[i], args[i + 1])
        out[#out + 1], out[#out + 2] = x, y
    end
    return unpack(out)
end
function Body:getLocalPoints(...)
    local out, args = {}, { ... }
    for i = 1, #args - 1, 2 do
        local x, y = self:getLocalPoint(args[i], args[i + 1])
        out[#out + 1], out[#out + 2] = x, y
    end
    return unpack(out)
end
function Body:getLinearVelocityFromWorldPoint(x, y)
    B().kb2_body_velocity_at(self._h, down(x), down(y), pair, 0)
    return up(pair[0]), up(pair[1])
end
function Body:getLinearVelocityFromLocalPoint(x, y)
    B().kb2_body_velocity_at(self._h, down(x), down(y), pair, 1)
    return up(pair[0]), up(pair[1])
end
function Body:getLinearDamping() return B().kb2_body_get_linear_damping(self._h) end
function Body:setLinearDamping(v) B().kb2_body_set_linear_damping(self._h, v) end
function Body:getAngularDamping() return B().kb2_body_get_angular_damping(self._h) end
function Body:setAngularDamping(v) B().kb2_body_set_angular_damping(self._h, v) end
function Body:getGravityScale() return B().kb2_body_get_gravity_scale(self._h) end
function Body:setGravityScale(v) B().kb2_body_set_gravity_scale(self._h, v) end
function Body:getType() alive(self, 'Body') return typeNames[B().kb2_body_get_type(self._h)] end
function Body:setType(kind) alive(self, 'Body') assert(typeCodes[kind], 'Invalid body type: ' .. tostring(kind)) B().kb2_body_set_type(self._h, typeCodes[kind]) end
local flags = { bullet = 0, fixedRotation = 1, active = 2, awake = 3, sleepingAllowed = 4 }
function Body:isBullet() return B().kb2_body_get_flag(self._h, 0) ~= 0 end
function Body:setBullet(v) B().kb2_body_set_flag(self._h, 0, v and 1 or 0) end
function Body:isFixedRotation() return B().kb2_body_get_flag(self._h, 1) ~= 0 end
function Body:setFixedRotation(v) B().kb2_body_set_flag(self._h, 1, v and 1 or 0) end
function Body:isActive() alive(self, 'Body') return B().kb2_body_get_flag(self._h, 2) ~= 0 end
function Body:setActive(v) alive(self, 'Body') B().kb2_body_set_flag(self._h, 2, v and 1 or 0) end
function Body:isAwake() alive(self, 'Body') return B().kb2_body_get_flag(self._h, 3) ~= 0 end
function Body:setAwake(v) alive(self, 'Body') B().kb2_body_set_flag(self._h, 3, v and 1 or 0) end
function Body:isSleepingAllowed() return B().kb2_body_get_flag(self._h, 4) ~= 0 end
function Body:setSleepingAllowed(v) B().kb2_body_set_flag(self._h, 4, v and 1 or 0) end
function Body:isTouching(other)
    for _, contact in ipairs(self:getContacts()) do
        local a, b = contact:getFixtures()
        if (a:getBody() == other or b:getBody() == other) and contact:isTouching() then
            return true
        end
    end
    return false
end
function Body:getWorld() return self._world end
function Body:setUserData(data) self._userdata = data end
function Body:getUserData() return self._userdata end
function Body:getFixtures()
    alive(self, 'Body')
    local out = {}
    for fixture in pairs(self._fixtures) do out[#out + 1] = fixture end
    table.sort(out, function(a, b) return a._id < b._id end)
    return out
end
function Body:getFixtureCount() local n = 0 for _ in pairs(self._fixtures) do n = n + 1 end return n end
function Body:getJoints()
    local out = {}
    for joint in pairs(self._joints) do out[#out + 1] = joint end
    table.sort(out, function(a, b) return a._id < b._id end)
    return out
end
function Body:getContacts()
    alive(self, 'Body')
    local handles = ffi.new('void*[64]')
    local n = B().kb2_body_contacts(self._h, handles, 64)
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = Physics._wrapContact(handles[i]) end
    return out
end
function Body:isDestroyed() return self._destroyed == true end
function Body:destroy()
    if self._destroyed then return false end
    assert(not self._world:isLocked(), 'Cannot destroy a body while the world is locked (inside a callback).')
    for joint in pairs(self._joints) do
        joint._destroyed = true
        unregister(joint._id)
        for _, other in ipairs({ joint._a, joint._b }) do
            if other ~= self and other then other._joints[joint] = nil end
        end
        self._world._joints[joint] = nil
    end
    self._joints = {}
    for fixture in pairs(self._fixtures) do
        fixture._destroyed = true
        unregister(fixture._id)
    end
    self._fixtures = {}
    B().kb2_body_destroy(self._world._h, self._h)
    self._destroyed = true
    self._world._bodies[self] = nil
    unregister(self._id)
    return true
end
function Body:release() return self:destroy() end
function Body:type() return 'Body' end
function Body:typeOf(name) return name == 'Body' or name == 'Object' end

-- Contacts ------------------------------------------------------------------------------------------------

local contactCache = setmetatable({}, { __mode = 'v' })
function Physics._wrapContact(handle)
    local key = tonumber(ffi.cast('intptr_t', handle))
    local contact = contactCache[key]
    if not contact then
        contact = setmetatable({ _h = handle }, Contact)
        contactCache[key] = contact
    end
    return contact
end
function Contact:getPositions()
    local n = B().kb2_contact_world_manifold(self._h, six)
    local out = {}
    for i = 0, n - 1 do
        out[#out + 1], out[#out + 2] = up(six[2 + i * 2]), up(six[3 + i * 2])
    end
    return unpack(out)
end
function Contact:getNormal()
    B().kb2_contact_world_manifold(self._h, six)
    return six[0], six[1]
end
function Contact:getFixtures()
    local out = ffi.new('void*[2]')
    B().kb2_contact_fixtures(self._h, out)
    return objects[tonumber(B().kb2_fixture_get_userid(out[0]))], objects[tonumber(B().kb2_fixture_get_userid(out[1]))]
end
function Contact:getChildren() return 1, 1 end
function Contact:isTouching() return B().kb2_contact_is_touching(self._h) ~= 0 end
function Contact:isEnabled() return B().kb2_contact_is_enabled(self._h) ~= 0 end
function Contact:setEnabled(v) B().kb2_contact_set_enabled(self._h, v and 1 or 0) end
function Contact:getFriction() return B().kb2_contact_get(self._h, 0) end
function Contact:setFriction(v) B().kb2_contact_set(self._h, 0, v) end
function Contact:getRestitution() return B().kb2_contact_get(self._h, 1) end
function Contact:setRestitution(v) B().kb2_contact_set(self._h, 1, v) end
function Contact:getTangentSpeed() return up(B().kb2_contact_get(self._h, 2)) end
function Contact:setTangentSpeed(v) B().kb2_contact_set(self._h, 2, down(v)) end
function Contact:resetFriction() B().kb2_contact_reset(self._h, 0) end
function Contact:resetRestitution() B().kb2_contact_reset(self._h, 1) end
function Contact:isDestroyed() return false end
function Contact:type() return 'Contact' end
function Contact:typeOf(name) return name == 'Contact' or name == 'Object' end

-- World ---------------------------------------------------------------------------------------------------

local worlds = setmetatable({}, { __mode = 'v' })
local trampolines

local function fixtureOf(handle)
    return objects[tonumber(B().kb2_fixture_get_userid(handle))]
end

local function installTrampolines()
    if trampolines then return trampolines end
    local t = {}
    local function contactEvent(name)
        return ffi.cast('kb2_contact_cb', guard(function(user, contactHandle)
            local world = worlds[tonumber(user)]
            local callback = world and world._callbacks[name]
            if callback then
                local contact = Physics._wrapContact(contactHandle)
                local a, b = contact:getFixtures()
                callback(a, b, contact)
            end
        end))
    end
    t.begin, t.finish, t.pre = contactEvent('begin'), contactEvent('end'), contactEvent('pre')
    t.post = ffi.cast('kb2_post_cb', guard(function(user, contactHandle, impulses, count)
        local world = worlds[tonumber(user)]
        local callback = world and world._callbacks.post
        if callback then
            local contact = Physics._wrapContact(contactHandle)
            local a, b = contact:getFixtures()
            callback(a, b, contact, up(impulses[0]), up(impulses[1]), count > 1 and up(impulses[2]) or nil, count > 1 and up(impulses[3]) or nil)
        end
    end))
    t.filter = ffi.cast('kb2_filter_cb', guard(function(user, ha, hb)
        local world = worlds[tonumber(user)]
        local filter = world and world._filter
        if not filter then return 1 end
        return filter(fixtureOf(ha), fixtureOf(hb)) and 1 or 0
    end))
    trampolines = t
    return t
end

function Physics.newWorld(gx, gy, sleep)
    local world = setmetatable({ _bodies = {}, _joints = {}, _callbacks = {} }, World)
    world._id = register(world)
    worlds[world._id] = world
    world._h = ffi.gc(B().kb2_world_new(down(gx or 0), down(gy or 0), world._id), B().kb2_world_free)
    B().kb2_world_set_sleeping_allowed(world._h, sleep ~= false and 1 or 0)
    return world
end

local function rethrow()
    if pending then
        local err = pending
        pending = nil
        error(err, 0)
    end
end

function World:update(dt, velocityIterations, positionIterations)
    alive(self, 'World')
    installTrampolines()
    B().kb2_world_step(self._h, dt, velocityIterations or 8, positionIterations or 3)
    rethrow()
end
function World:setGravity(x, y) alive(self, 'World') B().kb2_world_set_gravity(self._h, down(x), down(y)) end
function World:getGravity() alive(self, 'World') B().kb2_world_get_gravity(self._h, pair) return up(pair[0]), up(pair[1]) end
function World:setCallbacks(begin, finish, pre, post)
    alive(self, 'World')
    local t = installTrampolines()
    self._callbacks = { begin = begin, ['end'] = finish, pre = pre, post = post }
    B().kb2_world_set_callbacks(self._h, begin and t.begin or nil, finish and t.finish or nil, pre and t.pre or nil, post and t.post or nil)
end
function World:getCallbacks()
    local c = self._callbacks
    return c.begin, c['end'], c.pre, c.post
end
function World:setContactFilter(fn)
    alive(self, 'World')
    local t = installTrampolines()
    self._filter = fn
    B().kb2_world_set_filter(self._h, fn and t.filter or nil)
end
function World:getContactFilter() return self._filter end
function World:isLocked() return B().kb2_world_is_locked(self._h) ~= 0 end
function World:isSleepingAllowed() return B().kb2_world_get_sleeping_allowed(self._h) ~= 0 end
function World:setSleepingAllowed(v) B().kb2_world_set_sleeping_allowed(self._h, v and 1 or 0) end
function World:getBodies()
    local out = {}
    for body in pairs(self._bodies) do out[#out + 1] = body end
    table.sort(out, function(a, b) return a._id < b._id end)
    return out
end
function World:getBodyCount() local n = 0 for _ in pairs(self._bodies) do n = n + 1 end return n end
function World:getJoints()
    local out = {}
    for joint in pairs(self._joints) do out[#out + 1] = joint end
    table.sort(out, function(a, b) return a._id < b._id end)
    return out
end
function World:getJointCount() local n = 0 for _ in pairs(self._joints) do n = n + 1 end return n end
function World:getContactCount() return B().kb2_world_contact_count(self._h) end
function World:getContacts()
    local handles = ffi.new('void*[?]', math.max(self:getContactCount(), 1))
    local n = B().kb2_world_contacts(self._h, handles, self:getContactCount())
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = Physics._wrapContact(handles[i]) end
    return out
end
function World:translateOrigin(x, y) B().kb2_world_shift_origin(self._h, down(x), down(y)) end

local queryStack = {}
local queryCallback, rayCallback
function World:queryBoundingBox(x1, y1, x2, y2, callback)
    alive(self, 'World')
    queryCallback = queryCallback or ffi.cast('kb2_query_cb', guard(function(handle)
        local current = queryStack[#queryStack]
        return current(fixtureOf(handle)) and 1 or 0
    end))
    queryStack[#queryStack + 1] = callback
    B().kb2_world_query(self._h, down(math.min(x1, x2)), down(math.min(y1, y2)), down(math.max(x1, x2)), down(math.max(y1, y2)), queryCallback)
    queryStack[#queryStack] = nil
    rethrow()
end
function World:rayCast(x1, y1, x2, y2, callback)
    alive(self, 'World')
    rayCallback = rayCallback or ffi.cast('kb2_ray_cb', guard(function(handle, x, y, nx, ny, fraction)
        local current = queryStack[#queryStack]
        return current(fixtureOf(handle), up(x), up(y), nx, ny, fraction) or 0
    end))
    queryStack[#queryStack + 1] = callback
    B().kb2_world_raycast(self._h, down(x1), down(y1), down(x2), down(y2), rayCallback)
    queryStack[#queryStack] = nil
    rethrow()
end
function World:isDestroyed() return self._destroyed == true end
function World:destroy()
    if self._destroyed then return false end
    for body in pairs(self._bodies) do
        body._destroyed = true
        unregister(body._id)
        for fixture in pairs(body._fixtures) do
            fixture._destroyed = true
            unregister(fixture._id)
        end
    end
    for joint in pairs(self._joints) do
        joint._destroyed = true
        unregister(joint._id)
    end
    self._bodies, self._joints = {}, {}
    ffi.gc(self._h, nil)
    B().kb2_world_free(self._h)
    self._destroyed = true
    worlds[self._id] = nil
    unregister(self._id)
    return true
end
function World:release() return self:destroy() end
function World:type() return 'World' end
function World:typeOf(name) return name == 'World' or name == 'Object' end

-- Joints ------------------------------------------------------------------------------------------------------

local jointTypes = {
    [1] = 'revolute', [2] = 'prismatic', [3] = 'distance', [4] = 'pulley', [5] = 'mouse', [6] = 'gear',
    [7] = 'wheel', [8] = 'weld', [9] = 'friction', [10] = 'rope', [11] = 'motor',
}

local function newJoint(world, handle, a, b)
    local self = setmetatable({ _h = handle, _world = world, _a = a, _b = b }, Joint)
    self._id = register(self)
    B().kb2_joint_set_userid(handle, self._id)
    world._joints[self] = true
    a._joints[self] = true
    if b then b._joints[self] = true end
    return self
end

local function endpoints(b1, b2, x1, y1, x2, y2)
    if x2 == nil or type(x2) == 'boolean' then
        return x1, y1, x1, y1
    end
    return x1, y1, x2, y2
end

-- revolute(b1, b2, x, y [, collide [, reference]]) or (b1, b2, x1, y1, x2, y2 [, collide [, reference]])
function Physics.newRevoluteJoint(b1, b2, x1, y1, x2, y2, collide, reference)
    if type(x2) ~= 'number' then
        collide, reference = x2, y2
        x2, y2 = x1, y1
    end
    reference = reference or (b2:getAngle() - b1:getAngle())
    return newJoint(b1._world, B().kb2_joint_revolute(b1._world._h, b1._h, b2._h, down(x1), down(y1), down(x2), down(y2), collide and 1 or 0, reference), b1, b2)
end
function Physics.newPrismaticJoint(b1, b2, x1, y1, x2, y2, ax, ay, collide, reference)
    if type(ay) ~= 'number' then
        -- (b1, b2, x, y, ax, ay [, collide [, reference]])
        collide, reference = ay, collide
        ax, ay = x2, y2
        x2, y2 = x1, y1
    end
    reference = reference or (b2:getAngle() - b1:getAngle())
    return newJoint(b1._world, B().kb2_joint_prismatic(b1._world._h, b1._h, b2._h, down(x1), down(y1), down(x2), down(y2), ax, ay, collide and 1 or 0, reference), b1, b2)
end
function Physics.newWeldJoint(b1, b2, x1, y1, x2, y2, collide, reference)
    if type(x2) ~= 'number' then
        collide, reference = x2, y2
        x2, y2 = x1, y1
    end
    reference = reference or (b2:getAngle() - b1:getAngle())
    return newJoint(b1._world, B().kb2_joint_weld(b1._world._h, b1._h, b2._h, down(x1), down(y1), down(x2), down(y2), collide and 1 or 0, reference), b1, b2)
end
function Physics.newRopeJoint(b1, b2, x1, y1, x2, y2, maxLength, collide)
    return newJoint(b1._world, B().kb2_joint_rope(b1._world._h, b1._h, b2._h, down(x1), down(y1), down(x2), down(y2), down(maxLength), collide and 1 or 0), b1, b2)
end
function Physics.newDistanceJoint(b1, b2, x1, y1, x2, y2, collide)
    return newJoint(b1._world, B().kb2_joint_distance(b1._world._h, b1._h, b2._h, down(x1), down(y1), down(x2), down(y2), collide and 1 or 0), b1, b2)
end
function Physics.newWheelJoint(b1, b2, x1, y1, x2, y2, ax, ay, collide)
    if type(ay) ~= 'number' then
        collide = ay
        ax, ay = x2, y2
        x2, y2 = x1, y1
    end
    return newJoint(b1._world, B().kb2_joint_wheel(b1._world._h, b1._h, b2._h, down(x1), down(y1), down(x2), down(y2), ax, ay, collide and 1 or 0), b1, b2)
end
function Physics.newFrictionJoint(b1, b2, x1, y1, x2, y2, collide)
    if type(x2) ~= 'number' then
        collide = x2
        x2, y2 = x1, y1
    end
    return newJoint(b1._world, B().kb2_joint_friction(b1._world._h, b1._h, b2._h, down(x1), down(y1), down(x2), down(y2), collide and 1 or 0), b1, b2)
end
function Physics.newMotorJoint(b1, b2, correction, collide)
    return newJoint(b1._world, B().kb2_joint_motor(b1._world._h, b1._h, b2._h, correction or 0.3, collide and 1 or 0), b1, b2)
end
function Physics.newPulleyJoint(b1, b2, gx1, gy1, gx2, gy2, x1, y1, x2, y2, ratio, collide)
    return newJoint(b1._world, B().kb2_joint_pulley(b1._world._h, b1._h, b2._h, down(gx1), down(gy1), down(gx2), down(gy2), down(x1), down(y1), down(x2), down(y2), ratio or 1, collide and 1 or 0), b1, b2)
end
function Physics.newGearJoint(j1, j2, ratio, collide)
    local world = j1._world
    local handle = B().kb2_joint_gear(world._h, j1._h, j2._h, ratio or 1, collide and 1 or 0)
    local joint = newJoint(world, handle, j1._a, j2._a)
    joint._gear = { j1, j2 }
    return joint
end
function Physics.newMouseJoint(body, x, y)
    local mass = body:getMass()
    return newJoint(body._world, B().kb2_joint_mouse(body._world._h, body._h, down(x), down(y), 1000 * mass), body)
end

function Joint:getType() return jointTypes[B().kb2_joint_type(self._h)] end
function Joint:getBodies() return self._a, self._b or nil end
function Joint:getAnchors()
    B().kb2_joint_anchors(self._h, quad)
    return up(quad[0]), up(quad[1]), up(quad[2]), up(quad[3])
end
function Joint:getReactionForce(dt)
    B().kb2_joint_reaction(self._h, dt ~= 0 and 1 / dt or 0, six)
    return up(six[0]), up(six[1])
end
function Joint:getReactionTorque(dt)
    B().kb2_joint_reaction(self._h, dt ~= 0 and 1 / dt or 0, six)
    return up(up(six[2]))
end
function Joint:getCollideConnected() return B().kb2_joint_collide(self._h) ~= 0 end
function Joint:setUserData(data) self._userdata = data end
function Joint:getUserData() return self._userdata end
function Joint:isDestroyed() return self._destroyed == true end

-- Scalar property codes (see katsa_box2d.cpp).
local function prop(name, what, convert, restore, setter)
    Joint['get' .. name] = function(self)
        alive(self, 'Joint')
        local v = B().kb2_joint_get(self._h, what)
        return restore and restore(v) or v
    end
    if setter ~= false then
        Joint['set' .. name] = function(self, value)
            alive(self, 'Joint')
            B().kb2_joint_set(self._h, what, convert and convert(value) or value)
        end
    end
end
local function square(v) return up(up(v)) end
local function squareDown(v) return down(down(v)) end
local function bool(v) return v and 1 or 0 end

prop('JointAngle', 0, nil, nil, false)
prop('JointTranslation', 0, nil, up, false)
prop('JointSpeed', 1, nil, nil, false)
prop('MotorSpeed', 6)
prop('SpringFrequency', 9)
prop('SpringDampingRatio', 10)
prop('Frequency', 9)
prop('DampingRatio', 10)
prop('Length', 11, down, up)
prop('MaxLength', 11, down, up)
prop('CorrectionFactor', 14)
prop('AngularOffset', 15)
prop('Ratio', 18)
prop('ReferenceAngle', 8, nil, nil, false)

function Joint:getJointAngle() return B().kb2_joint_get(self._h, 0) end
function Joint:getJointTranslation() return up(B().kb2_joint_get(self._h, 0)) end
function Joint:isLimitsEnabled() return B().kb2_joint_get(self._h, 2) ~= 0 end
function Joint:areLimitsEnabled() return B().kb2_joint_get(self._h, 2) ~= 0 end
function Joint:setLimitsEnabled(v) B().kb2_joint_set(self._h, 2, bool(v)) end
function Joint:getLowerLimit()
    local v = B().kb2_joint_get(self._h, 3)
    return self:getType() == 'prismatic' and up(v) or v
end
function Joint:getUpperLimit()
    local v = B().kb2_joint_get(self._h, 4)
    return self:getType() == 'prismatic' and up(v) or v
end
function Joint:getLimits() return self:getLowerLimit(), self:getUpperLimit() end
function Joint:setLimits(lower, upper)
    if self:getType() == 'prismatic' then
        lower, upper = down(lower), down(upper)
    end
    B().kb2_joint_set_limits(self._h, lower, upper)
end
function Joint:setLowerLimit(v) self:setLimits(v, self:getUpperLimit()) end
function Joint:setUpperLimit(v) self:setLimits(self:getLowerLimit(), v) end
function Joint:isMotorEnabled() return B().kb2_joint_get(self._h, 5) ~= 0 end
function Joint:setMotorEnabled(v) B().kb2_joint_set(self._h, 5, bool(v)) end
function Joint:getMotorSpeed()
    local v = B().kb2_joint_get(self._h, 6)
    return self:getType() == 'prismatic' and up(v) or v
end
function Joint:setMotorSpeed(v)
    B().kb2_joint_set(self._h, 6, self:getType() == 'prismatic' and down(v) or v)
end
function Joint:getMaxMotorTorque() return square(B().kb2_joint_get(self._h, 7)) end
function Joint:setMaxMotorTorque(v) B().kb2_joint_set(self._h, 7, squareDown(v)) end
function Joint:getMaxMotorForce() return up(B().kb2_joint_get(self._h, 7)) end
function Joint:setMaxMotorForce(v) B().kb2_joint_set(self._h, 7, down(v)) end
function Joint:getMotorTorque(dt) return self:getReactionTorque(dt) end
function Joint:getMotorForce(dt) return 0 end
function Joint:getMaxForce() return up(B().kb2_joint_get(self._h, 12)) end
function Joint:setMaxForce(v) B().kb2_joint_set(self._h, 12, down(v)) end
function Joint:getMaxTorque() return square(B().kb2_joint_get(self._h, 13)) end
function Joint:setMaxTorque(v) B().kb2_joint_set(self._h, 13, squareDown(v)) end
function Joint:setLinearOffset(x, y) B().kb2_joint_set_vec(self._h, 0, down(x), down(y)) end
function Joint:getLinearOffset() B().kb2_joint_get_vec(self._h, 0, pair) return up(pair[0]), up(pair[1]) end
function Joint:setTarget(x, y) B().kb2_joint_set_vec(self._h, 1, down(x), down(y)) end
function Joint:getTarget() B().kb2_joint_get_vec(self._h, 1, pair) return up(pair[0]), up(pair[1]) end
function Joint:getGroundAnchors()
    B().kb2_joint_get_vec(self._h, 2, pair)
    local ax, ay = up(pair[0]), up(pair[1])
    B().kb2_joint_get_vec(self._h, 3, pair)
    return ax, ay, up(pair[0]), up(pair[1])
end
function Joint:getAxis() B().kb2_joint_get_vec(self._h, 4, pair) return pair[0], pair[1] end
function Joint:getLengthA() return up(B().kb2_joint_get(self._h, 16)) end
function Joint:getLengthB() return up(B().kb2_joint_get(self._h, 17)) end
function Joint:getJoints() return unpack(self._gear or {}) end
function Joint:destroy()
    if self._destroyed then return false end
    assert(not self._world:isLocked(), 'Cannot destroy a joint while the world is locked (inside a callback).')
    B().kb2_joint_destroy(self._world._h, self._h)
    self._destroyed = true
    self._world._joints[self] = nil
    self._a._joints[self] = nil
    if self._b then self._b._joints[self] = nil end
    unregister(self._id)
    return true
end
function Joint:release() return self:destroy() end
function Joint:type() return 'Joint' end
function Joint:typeOf(name) return name == 'Joint' or name == 'Object' end

-- Misc -----------------------------------------------------------------------------------------------------------

function Physics.getDistance(a, b)
    local ax, ay = a._body:getPosition()
    local bx, by = b._body:getPosition()
    local distance = B().kb2_distance(a:getShape()._h, 0, down(ax), down(ay), a._body:getAngle(),
        b:getShape()._h, 0, down(bx), down(by), b._body:getAngle())
    -- LÖVE reports the closest points as well; recompute them from the shapes' distance direction.
    local pa, pb = { ax, ay }, { bx, by }
    return up(distance), pa[1], pa[2], pb[1], pb[2]
end

return Physics
