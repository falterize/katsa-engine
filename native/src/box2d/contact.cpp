// katsa_box2d / contact: contacts between two fixtures (owned by Box2D; valid until the next
// step or until one of the fixtures is destroyed).
#include "bridge.h"

// out: { fixtureA, fixtureB }
KB2_EXPORT void kb2_contact_fixtures(void* contact, void** out) {
    b2Contact* c = asContact(contact);
    out[0] = c->GetFixtureA();
    out[1] = c->GetFixtureB();
}

// out: { normal.x, normal.y, point1.x, point1.y [, point2.x, point2.y] } in world coordinates.
// Returns the number of points (0..2); `out` needs room for 6 floats.
KB2_EXPORT int kb2_contact_world_manifold(void* contact, float* out) {
    b2Contact* c = asContact(contact);
    b2WorldManifold manifold;
    c->GetWorldManifold(&manifold);
    int count = c->GetManifold()->pointCount;
    writeVec(out, manifold.normal);
    for (int i = 0; i < count; i++) {
        writeVec(out + 2 + i * 2, manifold.points[i]);
    }
    return count;
}

KB2_EXPORT int kb2_contact_is_touching(void* contact) {
    return asContact(contact)->IsTouching();
}

KB2_EXPORT int kb2_contact_is_enabled(void* contact) {
    return asContact(contact)->IsEnabled();
}

// Only lasts for the current step: Box2D re-enables contacts every step, so this is meant to be
// called from the pre-solve callback.
KB2_EXPORT void kb2_contact_set_enabled(void* contact, int enabled) {
    asContact(contact)->SetEnabled(enabled != 0);
}

// `property` is a ContactProperty; unknown properties read as 0.
KB2_EXPORT float kb2_contact_get(void* contact, int property) {
    b2Contact* c = asContact(contact);
    switch (property) {
    case CONTACT_FRICTION:
        return c->GetFriction();
    case CONTACT_RESTITUTION:
        return c->GetRestitution();
    case CONTACT_TANGENT_SPEED:
        return c->GetTangentSpeed();
    }
    return 0;
}

// `property` is a ContactProperty; unknown properties are ignored.
KB2_EXPORT void kb2_contact_set(void* contact, int property, float value) {
    b2Contact* c = asContact(contact);
    switch (property) {
    case CONTACT_FRICTION:
        c->SetFriction(value);
        break;
    case CONTACT_RESTITUTION:
        c->SetRestitution(value);
        break;
    case CONTACT_TANGENT_SPEED:
        c->SetTangentSpeed(value);
        break;
    }
}

// Restores the friction (CONTACT_FRICTION) or, for any other code, the restitution mixed from the
// two fixtures.
KB2_EXPORT void kb2_contact_reset(void* contact, int property) {
    if (property == CONTACT_FRICTION) {
        asContact(contact)->ResetFriction();
    } else {
        asContact(contact)->ResetRestitution();
    }
}
