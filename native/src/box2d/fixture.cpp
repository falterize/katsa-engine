// katsa_box2d / fixture: shapes attached to bodies, with material and collision filtering.
#include "bridge.h"

// Attaches a copy of `shape` to `body`. Lua still owns (and may free) its own shape afterwards.
// Must not be called while the world is locked.
KB2_EXPORT void* kb2_fixture_new(void* body, void* shape, float density) {
    b2FixtureDef definition;
    definition.shape = asShape(shape);
    definition.density = density;
    return asBody(body)->CreateFixture(&definition);
}

KB2_EXPORT void kb2_fixture_destroy(void* body, void* fixture) {
    asBody(body)->DestroyFixture(asFixture(fixture));
}

// An integer Lua uses to find its object for this fixture (Box2D stores it as user data).
KB2_EXPORT void kb2_fixture_set_userid(void* fixture, intptr_t id) {
    asFixture(fixture)->SetUserData(reinterpret_cast<void*>(id));
}

KB2_EXPORT intptr_t kb2_fixture_get_userid(void* fixture) {
    return reinterpret_cast<intptr_t>(asFixture(fixture)->GetUserData());
}

KB2_EXPORT void* kb2_fixture_body(void* fixture) {
    return asFixture(fixture)->GetBody();
}

// The fixture's own shape, owned by Box2D (see shape.cpp): never pass it to kb2_shape_free.
KB2_EXPORT void* kb2_fixture_shape(void* fixture) {
    return asFixture(fixture)->GetShape();
}

// `property` is a FixtureProperty; unknown properties read as 0.
KB2_EXPORT float kb2_fixture_get(void* fixture, int property) {
    b2Fixture* f = asFixture(fixture);
    switch (property) {
    case FIXTURE_FRICTION:
        return f->GetFriction();
    case FIXTURE_RESTITUTION:
        return f->GetRestitution();
    case FIXTURE_DENSITY:
        return f->GetDensity();
    case FIXTURE_SENSOR:
        return f->IsSensor();
    }
    return 0;
}

// `property` is a FixtureProperty; unknown properties are ignored. Changing the density also
// recomputes the body's mass, as a density change alone would not take effect.
KB2_EXPORT void kb2_fixture_set(void* fixture, int property, float value) {
    b2Fixture* f = asFixture(fixture);
    switch (property) {
    case FIXTURE_FRICTION:
        f->SetFriction(value);
        break;
    case FIXTURE_RESTITUTION:
        f->SetRestitution(value);
        break;
    case FIXTURE_DENSITY:
        f->SetDensity(value);
        f->GetBody()->ResetMassData();
        break;
    case FIXTURE_SENSOR:
        f->SetSensor(value != 0);
        break;
    }
}

// out: { categoryBits, maskBits, groupIndex }
KB2_EXPORT void kb2_fixture_get_filter(void* fixture, int* out) {
    b2Filter filter = asFixture(fixture)->GetFilterData();
    out[0] = filter.categoryBits;
    out[1] = filter.maskBits;
    out[2] = filter.groupIndex;
}

// Category and mask are 16-bit masks; group is a signed 16-bit index.
KB2_EXPORT void kb2_fixture_set_filter(void* fixture, int category, int mask, int group) {
    b2Filter filter;
    filter.categoryBits = static_cast<uint16>(category);
    filter.maskBits = static_cast<uint16>(mask);
    filter.groupIndex = static_cast<int16>(group);
    asFixture(fixture)->SetFilterData(filter);
}

// (x, y) is a world point.
KB2_EXPORT int kb2_fixture_test_point(void* fixture, float x, float y) {
    return asFixture(fixture)->TestPoint(b2Vec2(x, y));
}

// Casts the world segment (x1, y1) -> (x2, y2) against one child of the fixture. On a hit
// writes { nx, ny, fraction } and returns 1.
KB2_EXPORT int kb2_fixture_raycast(void* fixture, float x1, float y1, float x2, float y2,
                                   float maxFraction, int child, float* out) {
    b2RayCastOutput hit;
    b2RayCastInput ray = makeRay(x1, y1, x2, y2, maxFraction);
    if (!asFixture(fixture)->RayCast(&hit, ray, child)) {
        return 0;
    }
    writeRayHit(out, hit);
    return 1;
}

// The broad-phase box of one child (slightly larger than the shape).
KB2_EXPORT void kb2_fixture_aabb(void* fixture, int child, float* out) {
    writeBox(out, asFixture(fixture)->GetAABB(child));
}

KB2_EXPORT void kb2_fixture_mass(void* fixture, float* out) {
    b2MassData mass;
    asFixture(fixture)->GetMassData(&mass);
    writeMass(out, mass);
}
