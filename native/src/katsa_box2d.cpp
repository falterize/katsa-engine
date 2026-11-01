// C interface to Box2D 2.3.1 for katsa.physics (LuaJIT FFI). All units are Box2D meters; the Lua
// side applies the pixel scale. Handles are raw pointers owned by the Lua objects.
#include <Box2D/Box2D.h>
#include <stdint.h>
#include <string.h>
#include <vector>

#if defined(_WIN32)
#define KB2 extern "C" __declspec(dllexport)
#else
#define KB2 extern "C" __attribute__((visibility("default")))
#endif

typedef void (*ContactCallback)(intptr_t user, void* contact);
typedef void (*PostSolveCallback)(intptr_t user, void* contact, const float* impulses, int count);
typedef int (*FilterCallback)(intptr_t user, void* fixtureA, void* fixtureB);
typedef int (*QueryCallback)(void* fixture);
typedef float (*RayCallback)(void* fixture, float x, float y, float nx, float ny, float fraction);

struct Listener : b2ContactListener, b2ContactFilter {
    intptr_t user = 0;
    ContactCallback begin_ = 0, end_ = 0, pre_ = 0;
    PostSolveCallback post_ = 0;
    FilterCallback filter_ = 0;
    void BeginContact(b2Contact* c) override { if (begin_) begin_(user, c); }
    void EndContact(b2Contact* c) override { if (end_) end_(user, c); }
    void PreSolve(b2Contact* c, const b2Manifold*) override { if (pre_) pre_(user, c); }
    void PostSolve(b2Contact* c, const b2ContactImpulse* i) override {
        if (!post_) return;
        float v[4] = { i->normalImpulses[0], i->tangentImpulses[0], i->normalImpulses[1], i->tangentImpulses[1] };
        post_(user, c, v, c->GetManifold()->pointCount);
    }
    bool ShouldCollide(b2Fixture* a, b2Fixture* b) override {
        if (filter_) return filter_(user, a, b) != 0;
        return b2ContactFilter::ShouldCollide(a, b);
    }
};

struct KWorld { b2World* world; Listener listener; b2Body* ground; };

// ------------------------------------------------------------------------------------ world

KB2 void* kb2_world_new(float gx, float gy, intptr_t user) {
    KWorld* w = new KWorld();
    w->listener.user = user;
    w->world = new b2World(b2Vec2(gx, gy));
    w->world->SetContactListener(&w->listener);
    w->world->SetContactFilter(&w->listener);
    b2BodyDef def;
    w->ground = w->world->CreateBody(&def);
    return w;
}
KB2 void kb2_world_free(void* h) { KWorld* w = (KWorld*)h; delete w->world; delete w; }
KB2 void kb2_world_step(void* h, float dt, int vi, int pi) { ((KWorld*)h)->world->Step(dt, vi, pi); }
KB2 void kb2_world_set_gravity(void* h, float x, float y) { ((KWorld*)h)->world->SetGravity(b2Vec2(x, y)); }
KB2 void kb2_world_get_gravity(void* h, float* out) { b2Vec2 g = ((KWorld*)h)->world->GetGravity(); out[0] = g.x; out[1] = g.y; }
KB2 void kb2_world_set_callbacks(void* h, ContactCallback b, ContactCallback e, ContactCallback p, PostSolveCallback s) {
    Listener& l = ((KWorld*)h)->listener; l.begin_ = b; l.end_ = e; l.pre_ = p; l.post_ = s;
}
KB2 void kb2_world_set_filter(void* h, FilterCallback f) { ((KWorld*)h)->listener.filter_ = f; }
KB2 int kb2_world_is_locked(void* h) { return ((KWorld*)h)->world->IsLocked(); }
KB2 void kb2_world_set_sleeping_allowed(void* h, int v) { ((KWorld*)h)->world->SetAllowSleeping(v != 0); }
KB2 int kb2_world_get_sleeping_allowed(void* h) { return ((KWorld*)h)->world->GetAllowSleeping(); }
KB2 int kb2_world_contact_count(void* h) { return ((KWorld*)h)->world->GetContactCount(); }
KB2 int kb2_world_contacts(void* h, void** out, int max) {
    int n = 0;
    for (b2Contact* c = ((KWorld*)h)->world->GetContactList(); c && n < max; c = c->GetNext()) out[n++] = c;
    return n;
}
KB2 void kb2_world_shift_origin(void* h, float x, float y) { ((KWorld*)h)->world->ShiftOrigin(b2Vec2(x, y)); }

struct QueryAdapter : b2QueryCallback {
    QueryCallback cb;
    bool ReportFixture(b2Fixture* f) override { return cb(f) != 0; }
};
KB2 void kb2_world_query(void* h, float lx, float ly, float ux, float uy, QueryCallback cb) {
    QueryAdapter q; q.cb = cb;
    b2AABB box; box.lowerBound.Set(lx, ly); box.upperBound.Set(ux, uy);
    ((KWorld*)h)->world->QueryAABB(&q, box);
}
struct RayAdapter : b2RayCastCallback {
    RayCallback cb;
    float32 ReportFixture(b2Fixture* f, const b2Vec2& p, const b2Vec2& n, float32 fraction) override {
        return cb(f, p.x, p.y, n.x, n.y, fraction);
    }
};
KB2 void kb2_world_raycast(void* h, float x1, float y1, float x2, float y2, RayCallback cb) {
    RayAdapter r; r.cb = cb;
    ((KWorld*)h)->world->RayCast(&r, b2Vec2(x1, y1), b2Vec2(x2, y2));
}

// ------------------------------------------------------------------------------------ body

KB2 void* kb2_body_new(void* h, int type, float x, float y, float angle) {
    b2BodyDef def;
    def.type = type == 0 ? b2_staticBody : type == 1 ? b2_dynamicBody : b2_kinematicBody;
    def.position.Set(x, y);
    def.angle = angle;
    return ((KWorld*)h)->world->CreateBody(&def);
}
KB2 void kb2_body_destroy(void* h, void* b) { ((KWorld*)h)->world->DestroyBody((b2Body*)b); }
KB2 void* kb2_world_ground(void* h) { return ((KWorld*)h)->ground; }
#define BODY ((b2Body*)b)
KB2 void kb2_body_set_userid(void* b, intptr_t id) { BODY->SetUserData((void*)id); }
KB2 intptr_t kb2_body_get_userid(void* b) { return (intptr_t)BODY->GetUserData(); }
KB2 void kb2_body_get_position(void* b, float* o) { b2Vec2 p = BODY->GetPosition(); o[0] = p.x; o[1] = p.y; }
KB2 float kb2_body_get_angle(void* b) { return BODY->GetAngle(); }
KB2 void kb2_body_set_transform(void* b, float x, float y, float a) { BODY->SetTransform(b2Vec2(x, y), a); }
KB2 void kb2_body_get_linear_velocity(void* b, float* o) { b2Vec2 v = BODY->GetLinearVelocity(); o[0] = v.x; o[1] = v.y; }
KB2 void kb2_body_set_linear_velocity(void* b, float x, float y) { BODY->SetLinearVelocity(b2Vec2(x, y)); }
KB2 float kb2_body_get_angular_velocity(void* b) { return BODY->GetAngularVelocity(); }
KB2 void kb2_body_set_angular_velocity(void* b, float v) { BODY->SetAngularVelocity(v); }
KB2 void kb2_body_apply_force(void* b, float fx, float fy, float px, float py, int point) {
    if (point) BODY->ApplyForce(b2Vec2(fx, fy), b2Vec2(px, py), true); else BODY->ApplyForceToCenter(b2Vec2(fx, fy), true);
}
KB2 void kb2_body_apply_impulse(void* b, float ix, float iy, float px, float py, int point) {
    if (point) BODY->ApplyLinearImpulse(b2Vec2(ix, iy), b2Vec2(px, py), true); else BODY->ApplyLinearImpulse(b2Vec2(ix, iy), BODY->GetWorldCenter(), true);
}
KB2 void kb2_body_apply_torque(void* b, float t) { BODY->ApplyTorque(t, true); }
KB2 void kb2_body_apply_angular_impulse(void* b, float i) { BODY->ApplyAngularImpulse(i, true); }
KB2 float kb2_body_get_mass(void* b) { return BODY->GetMass(); }
KB2 float kb2_body_get_inertia(void* b) { return BODY->GetInertia(); }
KB2 void kb2_body_get_mass_data(void* b, float* o) { b2MassData d; BODY->GetMassData(&d); o[0] = d.center.x; o[1] = d.center.y; o[2] = d.mass; o[3] = d.I; }
KB2 void kb2_body_set_mass_data(void* b, float cx, float cy, float m, float i) { b2MassData d; d.center.Set(cx, cy); d.mass = m; d.I = i; BODY->SetMassData(&d); }
KB2 void kb2_body_reset_mass(void* b) { BODY->ResetMassData(); }
KB2 void kb2_body_get_world_center(void* b, float* o) { b2Vec2 p = BODY->GetWorldCenter(); o[0] = p.x; o[1] = p.y; }
KB2 void kb2_body_get_local_center(void* b, float* o) { b2Vec2 p = BODY->GetLocalCenter(); o[0] = p.x; o[1] = p.y; }
KB2 void kb2_body_world_point(void* b, float x, float y, float* o) { b2Vec2 p = BODY->GetWorldPoint(b2Vec2(x, y)); o[0] = p.x; o[1] = p.y; }
KB2 void kb2_body_world_vector(void* b, float x, float y, float* o) { b2Vec2 p = BODY->GetWorldVector(b2Vec2(x, y)); o[0] = p.x; o[1] = p.y; }
KB2 void kb2_body_local_point(void* b, float x, float y, float* o) { b2Vec2 p = BODY->GetLocalPoint(b2Vec2(x, y)); o[0] = p.x; o[1] = p.y; }
KB2 void kb2_body_local_vector(void* b, float x, float y, float* o) { b2Vec2 p = BODY->GetLocalVector(b2Vec2(x, y)); o[0] = p.x; o[1] = p.y; }
KB2 void kb2_body_velocity_at(void* b, float x, float y, float* o, int local) {
    b2Vec2 p = local ? BODY->GetLinearVelocityFromLocalPoint(b2Vec2(x, y)) : BODY->GetLinearVelocityFromWorldPoint(b2Vec2(x, y));
    o[0] = p.x; o[1] = p.y;
}
KB2 float kb2_body_get_linear_damping(void* b) { return BODY->GetLinearDamping(); }
KB2 void kb2_body_set_linear_damping(void* b, float v) { BODY->SetLinearDamping(v); }
KB2 float kb2_body_get_angular_damping(void* b) { return BODY->GetAngularDamping(); }
KB2 void kb2_body_set_angular_damping(void* b, float v) { BODY->SetAngularDamping(v); }
KB2 float kb2_body_get_gravity_scale(void* b) { return BODY->GetGravityScale(); }
KB2 void kb2_body_set_gravity_scale(void* b, float v) { BODY->SetGravityScale(v); }
KB2 int kb2_body_get_type(void* b) { return BODY->GetType() == b2_staticBody ? 0 : BODY->GetType() == b2_dynamicBody ? 1 : 2; }
KB2 void kb2_body_set_type(void* b, int t) { BODY->SetType(t == 0 ? b2_staticBody : t == 1 ? b2_dynamicBody : b2_kinematicBody); }
KB2 int kb2_body_get_flag(void* b, int flag) {
    switch (flag) { case 0: return BODY->IsBullet(); case 1: return BODY->IsFixedRotation(); case 2: return BODY->IsActive();
    case 3: return BODY->IsAwake(); case 4: return BODY->IsSleepingAllowed(); } return 0;
}
KB2 void kb2_body_set_flag(void* b, int flag, int v) {
    switch (flag) { case 0: BODY->SetBullet(v != 0); break; case 1: BODY->SetFixedRotation(v != 0); break;
    case 2: BODY->SetActive(v != 0); break; case 3: BODY->SetAwake(v != 0); break; case 4: BODY->SetSleepingAllowed(v != 0); break; }
}
KB2 int kb2_body_fixtures(void* b, void** out, int max) {
    int n = 0; for (b2Fixture* f = BODY->GetFixtureList(); f && n < max; f = f->GetNext()) out[n++] = f; return n;
}
KB2 int kb2_body_contacts(void* b, void** out, int max) {
    int n = 0; for (b2ContactEdge* e = BODY->GetContactList(); e && n < max; e = e->next) out[n++] = e->contact; return n;
}
KB2 int kb2_body_joints(void* b, void** out, int max) {
    int n = 0; for (b2JointEdge* e = BODY->GetJointList(); e && n < max; e = e->next) out[n++] = e->joint; return n;
}

// ------------------------------------------------------------------------------------ shapes

KB2 void* kb2_shape_circle(float x, float y, float r) { b2CircleShape* s = new b2CircleShape(); s->m_p.Set(x, y); s->m_radius = r; return s; }
KB2 void* kb2_shape_polygon(const float* pts, int n) {
    if (n < 3 || n > b2_maxPolygonVertices) return 0;
    std::vector<b2Vec2> v(n);
    for (int i = 0; i < n; i++) v[i].Set(pts[i * 2], pts[i * 2 + 1]);
    b2PolygonShape* s = new b2PolygonShape(); s->Set(v.data(), n);
    return s;
}
KB2 void* kb2_shape_box(float hx, float hy, float cx, float cy, float angle) {
    b2PolygonShape* s = new b2PolygonShape(); s->SetAsBox(hx, hy, b2Vec2(cx, cy), angle); return s;
}
KB2 void* kb2_shape_edge(float x1, float y1, float x2, float y2) { b2EdgeShape* s = new b2EdgeShape(); s->Set(b2Vec2(x1, y1), b2Vec2(x2, y2)); return s; }
KB2 void* kb2_shape_chain(const float* pts, int n, int loop) {
    std::vector<b2Vec2> v(n);
    for (int i = 0; i < n; i++) v[i].Set(pts[i * 2], pts[i * 2 + 1]);
    b2ChainShape* s = new b2ChainShape();
    if (loop) s->CreateLoop(v.data(), n); else s->CreateChain(v.data(), n);
    return s;
}
KB2 void kb2_shape_free(void* s) { delete (b2Shape*)s; }
KB2 int kb2_shape_type(void* s) { switch (((b2Shape*)s)->GetType()) { case b2Shape::e_circle: return 0; case b2Shape::e_edge: return 1; case b2Shape::e_polygon: return 2; default: return 3; } }
KB2 float kb2_shape_radius(void* s) { return ((b2Shape*)s)->m_radius; }
KB2 void kb2_shape_set_radius(void* s, float r) { ((b2Shape*)s)->m_radius = r; }
KB2 int kb2_shape_child_count(void* s) { return ((b2Shape*)s)->GetChildCount(); }
KB2 int kb2_shape_points(void* s, float* out, int max) {
    b2Shape* sh = (b2Shape*)s; int n = 0;
    switch (sh->GetType()) {
    case b2Shape::e_circle: out[0] = ((b2CircleShape*)sh)->m_p.x; out[1] = ((b2CircleShape*)sh)->m_p.y; return 1;
    case b2Shape::e_edge: { b2EdgeShape* e = (b2EdgeShape*)sh; out[0] = e->m_vertex1.x; out[1] = e->m_vertex1.y; out[2] = e->m_vertex2.x; out[3] = e->m_vertex2.y; return 2; }
    case b2Shape::e_polygon: { b2PolygonShape* p = (b2PolygonShape*)sh; for (; n < p->m_count && n < max; n++) { out[n * 2] = p->m_vertices[n].x; out[n * 2 + 1] = p->m_vertices[n].y; } return n; }
    default: { b2ChainShape* c = (b2ChainShape*)sh; for (; n < c->m_count && n < max; n++) { out[n * 2] = c->m_vertices[n].x; out[n * 2 + 1] = c->m_vertices[n].y; } return n; }
    }
}
KB2 int kb2_shape_test_point(void* s, float x, float y, float angle, float px, float py) {
    b2Transform t; t.Set(b2Vec2(x, y), angle); return ((b2Shape*)s)->TestPoint(t, b2Vec2(px, py));
}
KB2 int kb2_shape_raycast(void* s, float x1, float y1, float x2, float y2, float maxFraction, float x, float y, float angle, int child, float* out) {
    b2RayCastInput in; in.p1.Set(x1, y1); in.p2.Set(x2, y2); in.maxFraction = maxFraction;
    b2Transform t; t.Set(b2Vec2(x, y), angle);
    b2RayCastOutput o;
    if (!((b2Shape*)s)->RayCast(&o, in, t, child)) return 0;
    out[0] = o.normal.x; out[1] = o.normal.y; out[2] = o.fraction; return 1;
}
KB2 void kb2_shape_aabb(void* s, float x, float y, float angle, int child, float* out) {
    b2Transform t; t.Set(b2Vec2(x, y), angle); b2AABB box; ((b2Shape*)s)->ComputeAABB(&box, t, child);
    out[0] = box.lowerBound.x; out[1] = box.lowerBound.y; out[2] = box.upperBound.x; out[3] = box.upperBound.y;
}
KB2 void kb2_shape_mass(void* s, float density, float* out) {
    b2MassData d; ((b2Shape*)s)->ComputeMass(&d, density); out[0] = d.center.x; out[1] = d.center.y; out[2] = d.mass; out[3] = d.I;
}
KB2 float kb2_distance(void* a, int ia, float ax, float ay, float aangle, void* b, int ib, float bx, float by, float bangle) {
    b2DistanceInput in; in.proxyA.Set((b2Shape*)a, ia); in.proxyB.Set((b2Shape*)b, ib);
    in.transformA.Set(b2Vec2(ax, ay), aangle); in.transformB.Set(b2Vec2(bx, by), bangle); in.useRadii = true;
    b2SimplexCache cache; cache.count = 0; b2DistanceOutput out;
    b2Distance(&out, &cache, &in);
    return out.distance;
}

// ------------------------------------------------------------------------------------ fixtures

KB2 void* kb2_fixture_new(void* body, void* shape, float density) {
    b2FixtureDef def; def.shape = (b2Shape*)shape; def.density = density;
    return ((b2Body*)body)->CreateFixture(&def);
}
KB2 void kb2_fixture_destroy(void* body, void* f) { ((b2Body*)body)->DestroyFixture((b2Fixture*)f); }
#define FIX ((b2Fixture*)f)
KB2 void kb2_fixture_set_userid(void* f, intptr_t id) { FIX->SetUserData((void*)id); }
KB2 intptr_t kb2_fixture_get_userid(void* f) { return (intptr_t)FIX->GetUserData(); }
KB2 void* kb2_fixture_body(void* f) { return FIX->GetBody(); }
KB2 void* kb2_fixture_shape(void* f) { return FIX->GetShape(); }
KB2 float kb2_fixture_get(void* f, int what) {
    switch (what) { case 0: return FIX->GetFriction(); case 1: return FIX->GetRestitution(); case 2: return FIX->GetDensity(); case 3: return FIX->IsSensor(); } return 0;
}
KB2 void kb2_fixture_set(void* f, int what, float v) {
    switch (what) { case 0: FIX->SetFriction(v); break; case 1: FIX->SetRestitution(v); break; case 2: FIX->SetDensity(v); FIX->GetBody()->ResetMassData(); break; case 3: FIX->SetSensor(v != 0); break; }
}
KB2 void kb2_fixture_get_filter(void* f, int* out) { b2Filter d = FIX->GetFilterData(); out[0] = d.categoryBits; out[1] = d.maskBits; out[2] = d.groupIndex; }
KB2 void kb2_fixture_set_filter(void* f, int cat, int mask, int group) { b2Filter d; d.categoryBits = (uint16)cat; d.maskBits = (uint16)mask; d.groupIndex = (int16)group; FIX->SetFilterData(d); }
KB2 int kb2_fixture_test_point(void* f, float x, float y) { return FIX->TestPoint(b2Vec2(x, y)); }
KB2 int kb2_fixture_raycast(void* f, float x1, float y1, float x2, float y2, float maxFraction, int child, float* out) {
    b2RayCastInput in; in.p1.Set(x1, y1); in.p2.Set(x2, y2); in.maxFraction = maxFraction;
    b2RayCastOutput o; if (!FIX->RayCast(&o, in, child)) return 0;
    out[0] = o.normal.x; out[1] = o.normal.y; out[2] = o.fraction; return 1;
}
KB2 void kb2_fixture_aabb(void* f, int child, float* out) {
    const b2AABB& box = FIX->GetAABB(child); out[0] = box.lowerBound.x; out[1] = box.lowerBound.y; out[2] = box.upperBound.x; out[3] = box.upperBound.y;
}
KB2 void kb2_fixture_mass(void* f, float* out) { b2MassData d; FIX->GetMassData(&d); out[0] = d.center.x; out[1] = d.center.y; out[2] = d.mass; out[3] = d.I; }

// ------------------------------------------------------------------------------------ contacts

#define CON ((b2Contact*)c)
KB2 void kb2_contact_fixtures(void* c, void** out) { out[0] = CON->GetFixtureA(); out[1] = CON->GetFixtureB(); }
KB2 int kb2_contact_world_manifold(void* c, float* out) {
    b2WorldManifold wm; CON->GetWorldManifold(&wm); int n = CON->GetManifold()->pointCount;
    out[0] = wm.normal.x; out[1] = wm.normal.y;
    for (int i = 0; i < n; i++) { out[2 + i * 2] = wm.points[i].x; out[3 + i * 2] = wm.points[i].y; }
    return n;
}
KB2 int kb2_contact_is_touching(void* c) { return CON->IsTouching(); }
KB2 int kb2_contact_is_enabled(void* c) { return CON->IsEnabled(); }
KB2 void kb2_contact_set_enabled(void* c, int v) { CON->SetEnabled(v != 0); }
KB2 float kb2_contact_get(void* c, int what) { switch (what) { case 0: return CON->GetFriction(); case 1: return CON->GetRestitution(); case 2: return CON->GetTangentSpeed(); } return 0; }
KB2 void kb2_contact_set(void* c, int what, float v) { switch (what) { case 0: CON->SetFriction(v); break; case 1: CON->SetRestitution(v); break; case 2: CON->SetTangentSpeed(v); break; } }
KB2 void kb2_contact_reset(void* c, int what) { if (what == 0) CON->ResetFriction(); else CON->ResetRestitution(); }

// ------------------------------------------------------------------------------------ joints

static b2Vec2 P(float x, float y) { return b2Vec2(x, y); }
static void setCommon(b2JointDef& d, b2Body* a, b2Body* b, int collide) { d.bodyA = a; d.bodyB = b; d.collideConnected = collide != 0; }

KB2 void* kb2_joint_revolute(void* w, void* a, void* b, float xa, float ya, float xb, float yb, int collide, float ref) {
    b2RevoluteJointDef d; setCommon(d, (b2Body*)a, (b2Body*)b, collide);
    d.localAnchorA = ((b2Body*)a)->GetLocalPoint(P(xa, ya)); d.localAnchorB = ((b2Body*)b)->GetLocalPoint(P(xb, yb));
    d.referenceAngle = ref; return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_prismatic(void* w, void* a, void* b, float xa, float ya, float xb, float yb, float ax, float ay, int collide, float ref) {
    b2PrismaticJointDef d; setCommon(d, (b2Body*)a, (b2Body*)b, collide);
    d.localAnchorA = ((b2Body*)a)->GetLocalPoint(P(xa, ya)); d.localAnchorB = ((b2Body*)b)->GetLocalPoint(P(xb, yb));
    b2Vec2 axis(ax, ay); axis.Normalize(); d.localAxisA = ((b2Body*)a)->GetLocalVector(axis); d.referenceAngle = ref;
    return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_weld(void* w, void* a, void* b, float xa, float ya, float xb, float yb, int collide, float ref) {
    b2WeldJointDef d; setCommon(d, (b2Body*)a, (b2Body*)b, collide);
    d.localAnchorA = ((b2Body*)a)->GetLocalPoint(P(xa, ya)); d.localAnchorB = ((b2Body*)b)->GetLocalPoint(P(xb, yb));
    d.referenceAngle = ref; return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_rope(void* w, void* a, void* b, float xa, float ya, float xb, float yb, float maxLength, int collide) {
    b2RopeJointDef d; setCommon(d, (b2Body*)a, (b2Body*)b, collide);
    d.localAnchorA = ((b2Body*)a)->GetLocalPoint(P(xa, ya)); d.localAnchorB = ((b2Body*)b)->GetLocalPoint(P(xb, yb));
    d.maxLength = maxLength; return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_distance(void* w, void* a, void* b, float xa, float ya, float xb, float yb, int collide) {
    b2DistanceJointDef d; d.Initialize((b2Body*)a, (b2Body*)b, P(xa, ya), P(xb, yb)); d.collideConnected = collide != 0;
    return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_wheel(void* w, void* a, void* b, float xa, float ya, float xb, float yb, float ax, float ay, int collide) {
    b2WheelJointDef d; setCommon(d, (b2Body*)a, (b2Body*)b, collide);
    d.localAnchorA = ((b2Body*)a)->GetLocalPoint(P(xa, ya)); d.localAnchorB = ((b2Body*)b)->GetLocalPoint(P(xb, yb));
    b2Vec2 axis(ax, ay); axis.Normalize(); d.localAxisA = ((b2Body*)a)->GetLocalVector(axis);
    return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_friction(void* w, void* a, void* b, float xa, float ya, float xb, float yb, int collide) {
    b2FrictionJointDef d; setCommon(d, (b2Body*)a, (b2Body*)b, collide);
    d.localAnchorA = ((b2Body*)a)->GetLocalPoint(P(xa, ya)); d.localAnchorB = ((b2Body*)b)->GetLocalPoint(P(xb, yb));
    return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_motor(void* w, void* a, void* b, float correction, int collide) {
    b2MotorJointDef d; d.Initialize((b2Body*)a, (b2Body*)b); d.collideConnected = collide != 0; d.correctionFactor = correction;
    return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_pulley(void* w, void* a, void* b, float gax, float gay, float gbx, float gby, float xa, float ya, float xb, float yb, float ratio, int collide) {
    b2PulleyJointDef d; d.Initialize((b2Body*)a, (b2Body*)b, P(gax, gay), P(gbx, gby), P(xa, ya), P(xb, yb), ratio); d.collideConnected = collide != 0;
    return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_gear(void* w, void* j1, void* j2, float ratio, int collide) {
    b2GearJointDef d; d.joint1 = (b2Joint*)j1; d.joint2 = (b2Joint*)j2; d.ratio = ratio; d.collideConnected = collide != 0;
    d.bodyA = d.joint1->GetBodyB(); d.bodyB = d.joint2->GetBodyB();
    return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void* kb2_joint_mouse(void* w, void* body, float x, float y, float maxForce) {
    b2MouseJointDef d; d.bodyA = ((KWorld*)w)->ground; d.bodyB = (b2Body*)body; d.target.Set(x, y);
    d.maxForce = maxForce; d.frequencyHz = 5.0f; d.dampingRatio = 0.7f; d.collideConnected = true;
    return ((KWorld*)w)->world->CreateJoint(&d);
}
KB2 void kb2_joint_destroy(void* w, void* j) { ((KWorld*)w)->world->DestroyJoint((b2Joint*)j); }
#define JT ((b2Joint*)j)
KB2 void kb2_joint_set_userid(void* j, intptr_t id) { JT->SetUserData((void*)id); }
KB2 int kb2_joint_type(void* j) { return (int)JT->GetType(); }
KB2 void kb2_joint_bodies(void* j, void** out) { out[0] = JT->GetBodyA(); out[1] = JT->GetBodyB(); }
KB2 void kb2_joint_anchors(void* j, float* o) { b2Vec2 a = JT->GetAnchorA(), b = JT->GetAnchorB(); o[0] = a.x; o[1] = a.y; o[2] = b.x; o[3] = b.y; }
KB2 void kb2_joint_reaction(void* j, float inv_dt, float* o) { b2Vec2 f = JT->GetReactionForce(inv_dt); o[0] = f.x; o[1] = f.y; o[2] = JT->GetReactionTorque(inv_dt); }
KB2 int kb2_joint_collide(void* j) { return JT->GetCollideConnected(); }

// Generic scalar properties; `what` codes are shared with the Lua wrapper.
KB2 float kb2_joint_get(void* j, int what) {
    switch (JT->GetType()) {
    case e_revoluteJoint: { b2RevoluteJoint* r = (b2RevoluteJoint*)j; switch (what) {
        case 0: return r->GetJointAngle(); case 1: return r->GetJointSpeed(); case 2: return r->IsLimitEnabled(); case 3: return r->GetLowerLimit();
        case 4: return r->GetUpperLimit(); case 5: return r->IsMotorEnabled(); case 6: return r->GetMotorSpeed(); case 7: return r->GetMaxMotorTorque(); case 8: return r->GetReferenceAngle(); } break; }
    case e_prismaticJoint: { b2PrismaticJoint* r = (b2PrismaticJoint*)j; switch (what) {
        case 0: return r->GetJointTranslation(); case 1: return r->GetJointSpeed(); case 2: return r->IsLimitEnabled(); case 3: return r->GetLowerLimit();
        case 4: return r->GetUpperLimit(); case 5: return r->IsMotorEnabled(); case 6: return r->GetMotorSpeed(); case 7: return r->GetMaxMotorForce(); case 8: return r->GetReferenceAngle(); } break; }
    case e_wheelJoint: { b2WheelJoint* r = (b2WheelJoint*)j; switch (what) {
        case 0: return r->GetJointTranslation(); case 1: return r->GetJointSpeed(); case 5: return r->IsMotorEnabled(); case 6: return r->GetMotorSpeed();
        case 7: return r->GetMaxMotorTorque(); case 9: return r->GetSpringFrequencyHz(); case 10: return r->GetSpringDampingRatio(); } break; }
    case e_distanceJoint: { b2DistanceJoint* r = (b2DistanceJoint*)j; switch (what) { case 11: return r->GetLength(); case 9: return r->GetFrequency(); case 10: return r->GetDampingRatio(); } break; }
    case e_weldJoint: { b2WeldJoint* r = (b2WeldJoint*)j; switch (what) { case 9: return r->GetFrequency(); case 10: return r->GetDampingRatio(); case 8: return r->GetReferenceAngle(); } break; }
    case e_ropeJoint: { b2RopeJoint* r = (b2RopeJoint*)j; switch (what) { case 11: return r->GetMaxLength(); } break; }
    case e_frictionJoint: { b2FrictionJoint* r = (b2FrictionJoint*)j; switch (what) { case 12: return r->GetMaxForce(); case 13: return r->GetMaxTorque(); } break; }
    case e_motorJoint: { b2MotorJoint* r = (b2MotorJoint*)j; switch (what) { case 12: return r->GetMaxForce(); case 13: return r->GetMaxTorque(); case 14: return r->GetCorrectionFactor(); case 15: return r->GetAngularOffset(); } break; }
    case e_pulleyJoint: { b2PulleyJoint* r = (b2PulleyJoint*)j; switch (what) { case 16: return r->GetLengthA(); case 17: return r->GetLengthB(); case 18: return r->GetRatio(); } break; }
    case e_gearJoint: { b2GearJoint* r = (b2GearJoint*)j; switch (what) { case 18: return r->GetRatio(); } break; }
    case e_mouseJoint: { b2MouseJoint* r = (b2MouseJoint*)j; switch (what) { case 12: return r->GetMaxForce(); case 9: return r->GetFrequency(); case 10: return r->GetDampingRatio(); } break; }
    default: break; }
    return 0;
}
KB2 void kb2_joint_set(void* j, int what, float v) {
    switch (JT->GetType()) {
    case e_revoluteJoint: { b2RevoluteJoint* r = (b2RevoluteJoint*)j; switch (what) {
        case 2: r->EnableLimit(v != 0); break; case 5: r->EnableMotor(v != 0); break; case 6: r->SetMotorSpeed(v); break; case 7: r->SetMaxMotorTorque(v); break; } break; }
    case e_prismaticJoint: { b2PrismaticJoint* r = (b2PrismaticJoint*)j; switch (what) {
        case 2: r->EnableLimit(v != 0); break; case 5: r->EnableMotor(v != 0); break; case 6: r->SetMotorSpeed(v); break; case 7: r->SetMaxMotorForce(v); break; } break; }
    case e_wheelJoint: { b2WheelJoint* r = (b2WheelJoint*)j; switch (what) {
        case 5: r->EnableMotor(v != 0); break; case 6: r->SetMotorSpeed(v); break; case 7: r->SetMaxMotorTorque(v); break; case 9: r->SetSpringFrequencyHz(v); break; case 10: r->SetSpringDampingRatio(v); break; } break; }
    case e_distanceJoint: { b2DistanceJoint* r = (b2DistanceJoint*)j; switch (what) { case 11: r->SetLength(v); break; case 9: r->SetFrequency(v); break; case 10: r->SetDampingRatio(v); break; } break; }
    case e_weldJoint: { b2WeldJoint* r = (b2WeldJoint*)j; switch (what) { case 9: r->SetFrequency(v); break; case 10: r->SetDampingRatio(v); break; } break; }
    case e_ropeJoint: { b2RopeJoint* r = (b2RopeJoint*)j; switch (what) { case 11: r->SetMaxLength(v); break; } break; }
    case e_frictionJoint: { b2FrictionJoint* r = (b2FrictionJoint*)j; switch (what) { case 12: r->SetMaxForce(v); break; case 13: r->SetMaxTorque(v); break; } break; }
    case e_motorJoint: { b2MotorJoint* r = (b2MotorJoint*)j; switch (what) { case 12: r->SetMaxForce(v); break; case 13: r->SetMaxTorque(v); break; case 14: r->SetCorrectionFactor(v); break; case 15: r->SetAngularOffset(v); break; } break; }
    case e_mouseJoint: { b2MouseJoint* r = (b2MouseJoint*)j; switch (what) { case 12: r->SetMaxForce(v); break; case 9: r->SetFrequency(v); break; case 10: r->SetDampingRatio(v); break; } break; }
    default: break; }
}
KB2 void kb2_joint_set_limits(void* j, float lower, float upper) {
    if (JT->GetType() == e_revoluteJoint) ((b2RevoluteJoint*)j)->SetLimits(lower, upper);
    else if (JT->GetType() == e_prismaticJoint) ((b2PrismaticJoint*)j)->SetLimits(lower, upper);
}
KB2 void kb2_joint_set_vec(void* j, int what, float x, float y) {
    if (JT->GetType() == e_motorJoint && what == 0) ((b2MotorJoint*)j)->SetLinearOffset(b2Vec2(x, y));
    else if (JT->GetType() == e_mouseJoint && what == 1) ((b2MouseJoint*)j)->SetTarget(b2Vec2(x, y));
}
KB2 void kb2_joint_get_vec(void* j, int what, float* o) {
    b2Vec2 v(0, 0);
    if (JT->GetType() == e_motorJoint && what == 0) v = ((b2MotorJoint*)j)->GetLinearOffset();
    else if (JT->GetType() == e_mouseJoint && what == 1) v = ((b2MouseJoint*)j)->GetTarget();
    else if (JT->GetType() == e_pulleyJoint && what == 2) v = ((b2PulleyJoint*)j)->GetGroundAnchorA();
    else if (JT->GetType() == e_pulleyJoint && what == 3) v = ((b2PulleyJoint*)j)->GetGroundAnchorB();
    else if (JT->GetType() == e_prismaticJoint && what == 4) v = ((b2PrismaticJoint*)j)->GetLocalAxisA();
    else if (JT->GetType() == e_wheelJoint && what == 4) v = ((b2WheelJoint*)j)->GetLocalAxisA();
    o[0] = v.x; o[1] = v.y;
}
