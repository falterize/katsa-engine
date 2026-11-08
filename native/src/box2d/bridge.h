// katsa_box2d: a flat C interface to Box2D 2.3.1 for katsa.physics (LuaJIT FFI).
//
// Files:
//   world.cpp     worlds, the contact listener, AABB queries and ray casts
//   body.cpp      bodies
//   shape.cpp     shapes (owned by Lua until attached) and shape distance
//   fixture.cpp   fixtures
//   contact.cpp   contacts
//   joint.cpp     joint creation and joint properties
//
// Conventions:
//   - Units are Box2D's: meters, radians, kilograms, seconds. The Lua side applies the pixel scale
//     (source/katsa/physics/scale.lua) and never sends pixels here.
//   - Handles are raw pointers. A world handle is a KWorld*; bodies, fixtures, joints and contacts
//     are the Box2D objects themselves. Box2D owns bodies, fixtures, joints and contacts and frees
//     them with their world; the Lua objects own the world and loose shapes.
//   - Results that are vectors are written into a caller-provided float array `out`.
//   - The integer codes below (body types, flags, property selectors) are part of the ABI: the
//     Lua files named next to each enum use the same numbers.
//   - Lua callbacks (contact events, filters, queries) are LuaJIT FFI callbacks. Box2D invokes them
//     during Step/Query/RayCast; while the world is locked they must not create or destroy bodies,
//     which the Lua side enforces by queueing contact events until the step ends.
#ifndef KATSA_BOX2D_BRIDGE_H
#define KATSA_BOX2D_BRIDGE_H

#include <Box2D/Box2D.h>
#include <stdint.h>

#if defined(_WIN32)
#define KB2_EXPORT extern "C" __declspec(dllexport)
#else
#define KB2_EXPORT extern "C" __attribute__((visibility("default")))
#endif

// ---------------------------------------------------------------------------------------------
// Callback types (implemented in Lua)
// ---------------------------------------------------------------------------------------------

// `user` is the value given to kb2_world_new: Lua uses it to find the world the event belongs to.
typedef void (*ContactCallback)(intptr_t user, void* contact);
// `impulses` holds { normal0, tangent0, normal1, tangent1 }; `count` is the manifold point count.
typedef void (*PostSolveCallback)(intptr_t user, void* contact, const float* impulses, int count);
// Returns non-zero when the two fixtures should collide.
typedef int (*FilterCallback)(intptr_t user, void* fixtureA, void* fixtureB);
// Returns non-zero to continue the query.
typedef int (*QueryCallback)(void* fixture);
// Box2D ray-cast protocol: return -1 to ignore the fixture, 0 to stop, `fraction` to clip the ray
// to this hit, 1 to continue unchanged.
typedef float (*RayCallback)(void* fixture, float x, float y, float nx, float ny, float fraction);

// ---------------------------------------------------------------------------------------------
// Codes shared with Lua
// ---------------------------------------------------------------------------------------------

// Body types. Lua: source/katsa/physics/body.lua (typeCodes / typeNames).
enum BodyTypeCode { BODY_STATIC = 0, BODY_DYNAMIC = 1, BODY_KINEMATIC = 2 };

// Body flags for kb2_body_get_flag / kb2_body_set_flag. Lua: source/katsa/physics/body.lua.
enum BodyFlag {
    FLAG_BULLET = 0,
    FLAG_FIXED_ROTATION = 1,
    FLAG_ACTIVE = 2,
    FLAG_AWAKE = 3,
    FLAG_SLEEPING_ALLOWED = 4,
};

// Shape types returned by kb2_shape_type. Lua: source/katsa/physics/shape.lua.
enum ShapeTypeCode { SHAPE_CIRCLE = 0, SHAPE_EDGE = 1, SHAPE_POLYGON = 2, SHAPE_CHAIN = 3 };

// Fixture scalar properties for kb2_fixture_get / kb2_fixture_set. Lua: physics/fixture.lua.
enum FixtureProperty {
    FIXTURE_FRICTION = 0,
    FIXTURE_RESTITUTION = 1,
    FIXTURE_DENSITY = 2,
    FIXTURE_SENSOR = 3, // 0 or 1
};

// Contact scalar properties for kb2_contact_get / kb2_contact_set; kb2_contact_reset accepts
// CONTACT_FRICTION (anything else resets restitution). Lua: physics/contact.lua.
enum ContactProperty {
    CONTACT_FRICTION = 0,
    CONTACT_RESTITUTION = 1,
    CONTACT_TANGENT_SPEED = 2,
};

// Joint scalar properties for kb2_joint_get / kb2_joint_set. Lua: physics/jointProperties.lua.
// A code means the same idea for every joint type that has it; a joint without the property
// returns 0 and ignores sets. Booleans are 0 or 1.
enum JointProperty {
    JOINT_VALUE = 0,            // angle (revolute) or translation (prismatic, wheel); read only
    JOINT_SPEED = 1,            // read only
    JOINT_LIMIT_ENABLED = 2,
    JOINT_LOWER_LIMIT = 3,      // read only; set both limits with kb2_joint_set_limits
    JOINT_UPPER_LIMIT = 4,      // read only
    JOINT_MOTOR_ENABLED = 5,
    JOINT_MOTOR_SPEED = 6,
    JOINT_MAX_MOTOR = 7,        // torque (revolute, wheel) or force (prismatic)
    JOINT_REFERENCE_ANGLE = 8,  // read only
    JOINT_FREQUENCY = 9,        // spring frequency in Hz
    JOINT_DAMPING_RATIO = 10,
    JOINT_LENGTH = 11,          // distance length, rope max length
    JOINT_MAX_FORCE = 12,
    JOINT_MAX_TORQUE = 13,
    JOINT_CORRECTION = 14,      // motor joint correction factor
    JOINT_ANGULAR_OFFSET = 15,  // motor joint
    JOINT_LENGTH_A = 16,        // pulley, read only
    JOINT_LENGTH_B = 17,        // pulley, read only
    JOINT_RATIO = 18,           // pulley, gear; read only
};

// Joint vector properties for kb2_joint_get_vec / kb2_joint_set_vec. Lua: physics/joint*.lua.
enum JointVector {
    JOINT_LINEAR_OFFSET = 0,   // motor joint
    JOINT_TARGET = 1,          // mouse joint
    JOINT_GROUND_ANCHOR_A = 2, // pulley, read only
    JOINT_GROUND_ANCHOR_B = 3, // pulley, read only
    JOINT_LOCAL_AXIS = 4,      // prismatic, wheel; read only
};

// ---------------------------------------------------------------------------------------------
// The world handle
// ---------------------------------------------------------------------------------------------

// Forwards Box2D's listener and filter virtual calls to the Lua callbacks. A null callback
// means "no Lua handler": events are skipped and filtering falls back to Box2D's default
// (category/mask/group bits).
struct Listener : b2ContactListener, b2ContactFilter {
    intptr_t user = 0;
    ContactCallback begin = nullptr;
    ContactCallback end = nullptr;
    ContactCallback preSolve = nullptr;
    PostSolveCallback postSolve = nullptr;
    FilterCallback filter = nullptr;

    void BeginContact(b2Contact* contact) override;
    void EndContact(b2Contact* contact) override;
    void PreSolve(b2Contact* contact, const b2Manifold* oldManifold) override;
    void PostSolve(b2Contact* contact, const b2ContactImpulse* impulse) override;
    bool ShouldCollide(b2Fixture* a, b2Fixture* b) override;
};

// What a world handle points to. `ground` is a static body without fixtures created with the
// world; mouse joints use it as their first body.
struct KWorld {
    b2World* world;
    Listener listener;
    b2Body* ground;
};

// Handle casts. Every exported function receives untyped pointers from Lua.
inline KWorld* asWorld(void* handle) { return static_cast<KWorld*>(handle); }
inline b2Body* asBody(void* handle) { return static_cast<b2Body*>(handle); }
inline b2Shape* asShape(void* handle) { return static_cast<b2Shape*>(handle); }
inline b2Fixture* asFixture(void* handle) { return static_cast<b2Fixture*>(handle); }
inline b2Contact* asContact(void* handle) { return static_cast<b2Contact*>(handle); }
inline b2Joint* asJoint(void* handle) { return static_cast<b2Joint*>(handle); }

// Writers for the `out` arrays.
inline void writeVec(float* out, const b2Vec2& v) {
    out[0] = v.x;
    out[1] = v.y;
}

// { center.x, center.y, mass, rotational inertia about the center }
inline void writeMass(float* out, const b2MassData& mass) {
    out[0] = mass.center.x;
    out[1] = mass.center.y;
    out[2] = mass.mass;
    out[3] = mass.I;
}

// { lower.x, lower.y, upper.x, upper.y }
inline void writeBox(float* out, const b2AABB& box) {
    out[0] = box.lowerBound.x;
    out[1] = box.lowerBound.y;
    out[2] = box.upperBound.x;
    out[3] = box.upperBound.y;
}

// { normal.x, normal.y, fraction }
inline void writeRayHit(float* out, const b2RayCastOutput& hit) {
    out[0] = hit.normal.x;
    out[1] = hit.normal.y;
    out[2] = hit.fraction;
}

inline b2Transform makeTransform(float x, float y, float angle) {
    b2Transform transform;
    transform.Set(b2Vec2(x, y), angle);
    return transform;
}

inline b2RayCastInput makeRay(float x1, float y1, float x2, float y2, float maxFraction) {
    b2RayCastInput ray;
    ray.p1.Set(x1, y1);
    ray.p2.Set(x2, y2);
    ray.maxFraction = maxFraction;
    return ray;
}

#endif
