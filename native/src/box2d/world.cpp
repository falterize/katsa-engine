// katsa_box2d / world: worlds, contact events, AABB queries and ray casts.
#include "bridge.h"

// ---------------------------------------------------------------------------------------------
// Listener: Box2D virtual calls -> Lua callbacks
// ---------------------------------------------------------------------------------------------

void Listener::BeginContact(b2Contact* contact) {
    if (begin) {
        begin(user, contact);
    }
}

void Listener::EndContact(b2Contact* contact) {
    if (end) {
        end(user, contact);
    }
}

void Listener::PreSolve(b2Contact* contact, const b2Manifold* /*oldManifold*/) {
    if (preSolve) {
        preSolve(user, contact);
    }
}

void Listener::PostSolve(b2Contact* contact, const b2ContactImpulse* impulse) {
    if (!postSolve) {
        return;
    }
    // Box2D 2.3 manifolds have at most two points; pass both slots, `count` says how many are real.
    float impulses[4] = {
        impulse->normalImpulses[0],
        impulse->tangentImpulses[0],
        impulse->normalImpulses[1],
        impulse->tangentImpulses[1],
    };
    postSolve(user, contact, impulses, contact->GetManifold()->pointCount);
}

bool Listener::ShouldCollide(b2Fixture* a, b2Fixture* b) {
    if (filter) {
        return filter(user, a, b) != 0;
    }
    return b2ContactFilter::ShouldCollide(a, b);
}

// ---------------------------------------------------------------------------------------------
// Lifetime and settings
// ---------------------------------------------------------------------------------------------

// `user` comes back as the first argument of every contact callback of this world.
KB2_EXPORT void* kb2_world_new(float gravityX, float gravityY, intptr_t user) {
    KWorld* world = new KWorld();
    world->listener.user = user;
    world->world = new b2World(b2Vec2(gravityX, gravityY));
    world->world->SetContactListener(&world->listener);
    world->world->SetContactFilter(&world->listener);
    b2BodyDef ground;
    world->ground = world->world->CreateBody(&ground);
    return world;
}

// Frees the world and everything Box2D owns in it (bodies, fixtures, joints, contacts).
KB2_EXPORT void kb2_world_free(void* handle) {
    KWorld* world = asWorld(handle);
    delete world->world;
    delete world;
}

KB2_EXPORT void kb2_world_step(void* handle, float dt, int velocityIterations,
                               int positionIterations) {
    asWorld(handle)->world->Step(dt, velocityIterations, positionIterations);
}

KB2_EXPORT void kb2_world_set_gravity(void* handle, float x, float y) {
    asWorld(handle)->world->SetGravity(b2Vec2(x, y));
}

KB2_EXPORT void kb2_world_get_gravity(void* handle, float* out) {
    writeVec(out, asWorld(handle)->world->GetGravity());
}

// Any callback may be null to switch that event off.
KB2_EXPORT void kb2_world_set_callbacks(void* handle, ContactCallback begin, ContactCallback end,
                                        ContactCallback preSolve, PostSolveCallback postSolve) {
    Listener& listener = asWorld(handle)->listener;
    listener.begin = begin;
    listener.end = end;
    listener.preSolve = preSolve;
    listener.postSolve = postSolve;
}

// Null restores Box2D's default filtering.
KB2_EXPORT void kb2_world_set_filter(void* handle, FilterCallback filter) {
    asWorld(handle)->listener.filter = filter;
}

// True during Step: bodies, fixtures and joints must not be created or destroyed then.
KB2_EXPORT int kb2_world_is_locked(void* handle) {
    return asWorld(handle)->world->IsLocked();
}

KB2_EXPORT void kb2_world_set_sleeping_allowed(void* handle, int allowed) {
    asWorld(handle)->world->SetAllowSleeping(allowed != 0);
}

KB2_EXPORT int kb2_world_get_sleeping_allowed(void* handle) {
    return asWorld(handle)->world->GetAllowSleeping();
}

// Moves the world origin; positions of everything shift by -(x, y). Used for large worlds.
KB2_EXPORT void kb2_world_shift_origin(void* handle, float x, float y) {
    asWorld(handle)->world->ShiftOrigin(b2Vec2(x, y));
}

KB2_EXPORT void* kb2_world_ground(void* handle) {
    return asWorld(handle)->ground;
}

// ---------------------------------------------------------------------------------------------
// Contacts of the world
// ---------------------------------------------------------------------------------------------

KB2_EXPORT int kb2_world_contact_count(void* handle) {
    return asWorld(handle)->world->GetContactCount();
}

// Writes up to `max` contact handles into `out`. Returns how many were written.
KB2_EXPORT int kb2_world_contacts(void* handle, void** out, int max) {
    int count = 0;
    b2Contact* contact = asWorld(handle)->world->GetContactList();
    for (; contact && count < max; contact = contact->GetNext()) {
        out[count++] = contact;
    }
    return count;
}

// ---------------------------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------------------------

namespace {

struct QueryAdapter : b2QueryCallback {
    QueryCallback callback;
    bool ReportFixture(b2Fixture* fixture) override { return callback(fixture) != 0; }
};

struct RayAdapter : b2RayCastCallback {
    RayCallback callback;
    float32 ReportFixture(b2Fixture* fixture, const b2Vec2& point, const b2Vec2& normal,
                          float32 fraction) override {
        return callback(fixture, point.x, point.y, normal.x, normal.y, fraction);
    }
};

} // namespace

// Calls `callback` for every fixture whose bounding box overlaps the box (lower, upper).
KB2_EXPORT void kb2_world_query(void* handle, float lowerX, float lowerY, float upperX,
                                float upperY, QueryCallback callback) {
    QueryAdapter query;
    query.callback = callback;
    b2AABB box;
    box.lowerBound.Set(lowerX, lowerY);
    box.upperBound.Set(upperX, upperY);
    asWorld(handle)->world->QueryAABB(&query, box);
}

// Calls `callback` for fixtures hit by the segment (x1, y1) -> (x2, y2), in no particular order.
KB2_EXPORT void kb2_world_raycast(void* handle, float x1, float y1, float x2, float y2,
                                  RayCallback callback) {
    RayAdapter ray;
    ray.callback = callback;
    asWorld(handle)->world->RayCast(&ray, b2Vec2(x1, y1), b2Vec2(x2, y2));
}
