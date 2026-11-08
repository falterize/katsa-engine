// katsa_box2d / body: creating bodies and reading or changing their state.
#include "bridge.h"

namespace {

b2BodyType toBox2DType(int code) {
    switch (code) {
    case BODY_STATIC:
        return b2_staticBody;
    case BODY_DYNAMIC:
        return b2_dynamicBody;
    default:
        return b2_kinematicBody;
    }
}

int toTypeCode(b2BodyType type) {
    switch (type) {
    case b2_staticBody:
        return BODY_STATIC;
    case b2_dynamicBody:
        return BODY_DYNAMIC;
    default:
        return BODY_KINEMATIC;
    }
}

} // namespace

// ---------------------------------------------------------------------------------------------
// Lifetime
// ---------------------------------------------------------------------------------------------

// `type` is a BodyTypeCode. Must not be called while the world is locked.
KB2_EXPORT void* kb2_body_new(void* world, int type, float x, float y, float angle) {
    b2BodyDef definition;
    definition.type = toBox2DType(type);
    definition.position.Set(x, y);
    definition.angle = angle;
    return asWorld(world)->world->CreateBody(&definition);
}

// Also destroys the body's fixtures and joints.
KB2_EXPORT void kb2_body_destroy(void* world, void* body) {
    asWorld(world)->world->DestroyBody(asBody(body));
}

// An integer Lua uses to find its object for this body (Box2D stores it as user data).
KB2_EXPORT void kb2_body_set_userid(void* body, intptr_t id) {
    asBody(body)->SetUserData(reinterpret_cast<void*>(id));
}

KB2_EXPORT intptr_t kb2_body_get_userid(void* body) {
    return reinterpret_cast<intptr_t>(asBody(body)->GetUserData());
}

// ---------------------------------------------------------------------------------------------
// Transform and velocity
// ---------------------------------------------------------------------------------------------

KB2_EXPORT void kb2_body_get_position(void* body, float* out) {
    writeVec(out, asBody(body)->GetPosition());
}

KB2_EXPORT float kb2_body_get_angle(void* body) {
    return asBody(body)->GetAngle();
}

KB2_EXPORT void kb2_body_set_transform(void* body, float x, float y, float angle) {
    asBody(body)->SetTransform(b2Vec2(x, y), angle);
}

KB2_EXPORT void kb2_body_get_linear_velocity(void* body, float* out) {
    writeVec(out, asBody(body)->GetLinearVelocity());
}

KB2_EXPORT void kb2_body_set_linear_velocity(void* body, float x, float y) {
    asBody(body)->SetLinearVelocity(b2Vec2(x, y));
}

KB2_EXPORT float kb2_body_get_angular_velocity(void* body) {
    return asBody(body)->GetAngularVelocity();
}

KB2_EXPORT void kb2_body_set_angular_velocity(void* body, float velocity) {
    asBody(body)->SetAngularVelocity(velocity);
}

// Velocity of a point of the body, given in body-local (`local` != 0) or world coordinates.
KB2_EXPORT void kb2_body_velocity_at(void* body, float x, float y, float* out, int local) {
    b2Body* b = asBody(body);
    b2Vec2 point(x, y);
    writeVec(out, local ? b->GetLinearVelocityFromLocalPoint(point)
                        : b->GetLinearVelocityFromWorldPoint(point));
}

// ---------------------------------------------------------------------------------------------
// Forces (all of them wake the body)
// ---------------------------------------------------------------------------------------------

// With `atPoint` the force acts at the world point (px, py), otherwise at the center of mass.
KB2_EXPORT void kb2_body_apply_force(void* body, float fx, float fy, float px, float py,
                                     int atPoint) {
    b2Body* b = asBody(body);
    if (atPoint) {
        b->ApplyForce(b2Vec2(fx, fy), b2Vec2(px, py), true);
    } else {
        b->ApplyForceToCenter(b2Vec2(fx, fy), true);
    }
}

KB2_EXPORT void kb2_body_apply_impulse(void* body, float ix, float iy, float px, float py,
                                       int atPoint) {
    b2Body* b = asBody(body);
    b2Vec2 point = atPoint ? b2Vec2(px, py) : b->GetWorldCenter();
    b->ApplyLinearImpulse(b2Vec2(ix, iy), point, true);
}

KB2_EXPORT void kb2_body_apply_torque(void* body, float torque) {
    asBody(body)->ApplyTorque(torque, true);
}

KB2_EXPORT void kb2_body_apply_angular_impulse(void* body, float impulse) {
    asBody(body)->ApplyAngularImpulse(impulse, true);
}

// ---------------------------------------------------------------------------------------------
// Mass
// ---------------------------------------------------------------------------------------------

KB2_EXPORT float kb2_body_get_mass(void* body) {
    return asBody(body)->GetMass();
}

KB2_EXPORT float kb2_body_get_inertia(void* body) {
    return asBody(body)->GetInertia();
}

// out: { center.x, center.y, mass, inertia } with the center in body coordinates.
KB2_EXPORT void kb2_body_get_mass_data(void* body, float* out) {
    b2MassData mass;
    asBody(body)->GetMassData(&mass);
    writeMass(out, mass);
}

// Overrides the mass computed from fixtures until kb2_body_reset_mass.
KB2_EXPORT void kb2_body_set_mass_data(void* body, float centerX, float centerY, float mass,
                                       float inertia) {
    b2MassData data;
    data.center.Set(centerX, centerY);
    data.mass = mass;
    data.I = inertia;
    asBody(body)->SetMassData(&data);
}

KB2_EXPORT void kb2_body_reset_mass(void* body) {
    asBody(body)->ResetMassData();
}

KB2_EXPORT void kb2_body_get_world_center(void* body, float* out) {
    writeVec(out, asBody(body)->GetWorldCenter());
}

KB2_EXPORT void kb2_body_get_local_center(void* body, float* out) {
    writeVec(out, asBody(body)->GetLocalCenter());
}

// ---------------------------------------------------------------------------------------------
// Coordinate conversion (points move with the body, vectors only rotate)
// ---------------------------------------------------------------------------------------------

KB2_EXPORT void kb2_body_world_point(void* body, float x, float y, float* out) {
    writeVec(out, asBody(body)->GetWorldPoint(b2Vec2(x, y)));
}

KB2_EXPORT void kb2_body_world_vector(void* body, float x, float y, float* out) {
    writeVec(out, asBody(body)->GetWorldVector(b2Vec2(x, y)));
}

KB2_EXPORT void kb2_body_local_point(void* body, float x, float y, float* out) {
    writeVec(out, asBody(body)->GetLocalPoint(b2Vec2(x, y)));
}

KB2_EXPORT void kb2_body_local_vector(void* body, float x, float y, float* out) {
    writeVec(out, asBody(body)->GetLocalVector(b2Vec2(x, y)));
}

// ---------------------------------------------------------------------------------------------
// Damping, gravity scale, type and flags
// ---------------------------------------------------------------------------------------------

KB2_EXPORT float kb2_body_get_linear_damping(void* body) {
    return asBody(body)->GetLinearDamping();
}

KB2_EXPORT void kb2_body_set_linear_damping(void* body, float damping) {
    asBody(body)->SetLinearDamping(damping);
}

KB2_EXPORT float kb2_body_get_angular_damping(void* body) {
    return asBody(body)->GetAngularDamping();
}

KB2_EXPORT void kb2_body_set_angular_damping(void* body, float damping) {
    asBody(body)->SetAngularDamping(damping);
}

KB2_EXPORT float kb2_body_get_gravity_scale(void* body) {
    return asBody(body)->GetGravityScale();
}

KB2_EXPORT void kb2_body_set_gravity_scale(void* body, float scale) {
    asBody(body)->SetGravityScale(scale);
}

KB2_EXPORT int kb2_body_get_type(void* body) {
    return toTypeCode(asBody(body)->GetType());
}

KB2_EXPORT void kb2_body_set_type(void* body, int type) {
    asBody(body)->SetType(toBox2DType(type));
}

// `flag` is a BodyFlag; unknown flags read as 0.
KB2_EXPORT int kb2_body_get_flag(void* body, int flag) {
    b2Body* b = asBody(body);
    switch (flag) {
    case FLAG_BULLET:
        return b->IsBullet();
    case FLAG_FIXED_ROTATION:
        return b->IsFixedRotation();
    case FLAG_ACTIVE:
        return b->IsActive();
    case FLAG_AWAKE:
        return b->IsAwake();
    case FLAG_SLEEPING_ALLOWED:
        return b->IsSleepingAllowed();
    }
    return 0;
}

// `flag` is a BodyFlag; unknown flags are ignored.
KB2_EXPORT void kb2_body_set_flag(void* body, int flag, int value) {
    b2Body* b = asBody(body);
    bool on = value != 0;
    switch (flag) {
    case FLAG_BULLET:
        b->SetBullet(on);
        break;
    case FLAG_FIXED_ROTATION:
        b->SetFixedRotation(on);
        break;
    case FLAG_ACTIVE:
        b->SetActive(on);
        break;
    case FLAG_AWAKE:
        b->SetAwake(on);
        break;
    case FLAG_SLEEPING_ALLOWED:
        b->SetSleepingAllowed(on);
        break;
    }
}

// ---------------------------------------------------------------------------------------------
// Attached objects. Each writes up to `max` handles into `out` and returns how many it wrote.
// ---------------------------------------------------------------------------------------------

KB2_EXPORT int kb2_body_fixtures(void* body, void** out, int max) {
    int count = 0;
    for (b2Fixture* f = asBody(body)->GetFixtureList(); f && count < max; f = f->GetNext()) {
        out[count++] = f;
    }
    return count;
}

KB2_EXPORT int kb2_body_contacts(void* body, void** out, int max) {
    int count = 0;
    for (b2ContactEdge* e = asBody(body)->GetContactList(); e && count < max; e = e->next) {
        out[count++] = e->contact;
    }
    return count;
}

KB2_EXPORT int kb2_body_joints(void* body, void** out, int max) {
    int count = 0;
    for (b2JointEdge* e = asBody(body)->GetJointList(); e && count < max; e = e->next) {
        out[count++] = e->joint;
    }
    return count;
}
