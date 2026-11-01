/* Project-owned bridge. Workers never enter Lua or retain Lua-owned memory. */
#include "joltc.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#define EXPORT __declspec(dllexport)
typedef CRITICAL_SECTION Mutex;
static void lock(Mutex *m) {
    EnterCriticalSection(m);
}
static void unlock(Mutex *m) {
    LeaveCriticalSection(m);
}
static void initialize(Mutex *m) {
    InitializeCriticalSection(m);
}
static void dispose(Mutex *m) {
    DeleteCriticalSection(m);
}
static uintptr_t thread_id(void) {
    return GetCurrentThreadId();
}
#else
#include <pthread.h>
#define EXPORT __attribute__((visibility("default")))
typedef pthread_mutex_t Mutex;
static void lock(Mutex *m) {
    pthread_mutex_lock(m);
}
static void unlock(Mutex *m) {
    pthread_mutex_unlock(m);
}
static void initialize(Mutex *m) {
    pthread_mutex_init(m, NULL);
}
static void dispose(Mutex *m) {
    pthread_mutex_destroy(m);
}
static uintptr_t thread_id(void) {
    return (uintptr_t)pthread_self();
}
#endif

/* Ordered ABI: Lua supplies addresses from the exact loaded joltc binary. */
#define FUNCTIONS(X)                                                                               \
    X(JPH_Body_GetID)                                                                              \
    X(JPH_ContactManifold_GetSubShapeID1)                                                          \
    X(JPH_ContactManifold_GetSubShapeID2)                                                          \
    X(JPH_ContactManifold_GetWorldSpaceNormal)                                                     \
    X(JPH_Shape_GetType)                                                                           \
    X(JPH_CompoundShape_GetSubShapeIndexFromID)                                                    \
    X(JPH_ContactListener_SetProcs)                                                                \
    X(JPH_Body_GetPosition)                                                                        \
    X(JPH_Body_GetRotation)                                                                        \
    X(JPH_Body_GetLinearVelocity)                                                                  \
    X(JPH_Body_GetAngularVelocity)
#define DECLARE(name) static __typeof__(&name) p_##name;
FUNCTIONS(DECLARE)

typedef struct Material {
    float friction, restitution;
} Material;
typedef struct Body {
    uint32_t id, occupied;
    const JPH_Shape *shape;
    Material *materials;
    uint32_t count, capacity;
} Body;
typedef struct Pair {
    uint32_t a, b;
} Pair;
typedef struct Event {
    uint32_t a, subA, b, subB, added;
    float x, y, z;
} Event;
typedef struct State {
    JPH_RVec3 position;
    JPH_Quat rotation;
    JPH_Vec3 linear, angular;
} State;
typedef struct Context {
    Mutex mutex;
    Body *bodies;
    uint32_t slots;
    Pair *excluded;
    size_t excludedCount, excludedCapacity;
    Event *events;
    size_t count, capacity;
    uint32_t failed;
    uintptr_t caller;
    uint64_t workerCallbacks, callerCallbacks;
} Context;

static Body *body(Context *c, uint32_t id) {
    uint32_t slot = (id * 2654435761u) & (c->slots - 1);
    while (c->bodies[slot].occupied) {
        if (c->bodies[slot].id == id)
            return &c->bodies[slot];
        slot = (slot + 1) & (c->slots - 1);
    }
    return &c->bodies[slot];
}

static Material material(Body *b, uint32_t sub) {
    uint32_t index = 0, remainder;
    if (b->shape && p_JPH_Shape_GetType(b->shape) == JPH_ShapeType_Compound)
        index = p_JPH_CompoundShape_GetSubShapeIndexFromID((const JPH_CompoundShape *)b->shape, sub,
                                                           &remainder);
    if (index >= b->count)
        index = 0;
    return b->count ? b->materials[index] : (Material){0.5f, 0.0f};
}

static void append(Context *c, Event e) {
    lock(&c->mutex);
    if (thread_id() == c->caller)
        ++c->callerCallbacks;
    else
        ++c->workerCallbacks;
    if (c->count == c->capacity) {
        size_t capacity = c->capacity ? c->capacity * 2 : 256;
        Event *events = realloc(c->events, capacity * sizeof(Event));
        if (!events) {
            c->failed = 1;
            unlock(&c->mutex);
            return;
        }
        c->events = events;
        c->capacity = capacity;
    }
    c->events[c->count++] = e;
    unlock(&c->mutex);
}

static JPH_ValidateResult JPH_API_CALL validate(void *user, const JPH_Body *a, const JPH_Body *b,
                                                const JPH_RVec3 *offset,
                                                const JPH_CollideShapeResult *result) {
    Context *c = user;
    uint32_t ai = p_JPH_Body_GetID(a), bi = p_JPH_Body_GetID(b);
    (void)offset;
    (void)result;
    for (size_t i = 0; i < c->excludedCount; ++i) {
        Pair p = c->excluded[i];
        if ((p.a == ai && p.b == bi) || (p.a == bi && p.b == ai))
            return JPH_ValidateResult_RejectAllContactsForThisBodyPair;
    }
    return JPH_ValidateResult_AcceptAllContactsForThisBodyPair;
}

static void JPH_API_CALL contact(void *user, const JPH_Body *a, const JPH_Body *b,
                                 const JPH_ContactManifold *manifold,
                                 JPH_ContactSettings *settings) {
    Context *c = user;
    Event e = {0};
    e.a = p_JPH_Body_GetID(a);
    e.b = p_JPH_Body_GetID(b);
    e.subA = p_JPH_ContactManifold_GetSubShapeID1(manifold);
    e.subB = p_JPH_ContactManifold_GetSubShapeID2(manifold);
    e.added = 1;
    JPH_Vec3 normal;
    p_JPH_ContactManifold_GetWorldSpaceNormal(manifold, &normal);
    e.x = normal.x;
    e.y = normal.y;
    e.z = normal.z;
    Material first = material(body(c, e.a), e.subA);
    Material second = material(body(c, e.b), e.subB);
    settings->combinedFriction = sqrtf(first.friction * second.friction);
    settings->combinedRestitution = sqrtf(first.restitution * second.restitution);
    append(c, e);
}

static void JPH_API_CALL removed(void *user, const JPH_SubShapeIDPair *pair) {
    Event e = {pair->Body1ID, pair->subShapeID1, pair->Body2ID, pair->subShapeID2, 0, 0, 0, 0};
    append(user, e);
}

EXPORT uint32_t KP_Install(void **functions) {
    unsigned index = 0;
#define ASSIGN(name)                                                                               \
    p_##name = (__typeof__(&name))functions[index++];                                              \
    if (!p_##name)                                                                                 \
        return 0;
    FUNCTIONS(ASSIGN)
    static JPH_ContactListener_Procs procs = {validate, contact, contact, removed};
    p_JPH_ContactListener_SetProcs(&procs);
    return 1;
}

EXPORT void KP_QueueJob(void *context, JPH_JobFunction *job, void *argument) {
    (void)context;
    job(argument);
}

EXPORT void KP_QueueJobs(void *context, JPH_JobFunction *job, void **arguments, uint32_t count) {
    (void)context;
    for (uint32_t i = 0; i < count; ++i)
        job(arguments[i]);
}

EXPORT void KP_ReadBody(JPH_Body *body, State *state) {
    p_JPH_Body_GetPosition(body, &state->position);
    p_JPH_Body_GetRotation(body, &state->rotation);
    p_JPH_Body_GetLinearVelocity(body, &state->linear);
    p_JPH_Body_GetAngularVelocity(body, &state->angular);
}

EXPORT Context *KP_Create(uint32_t maxBodies) {
    if (maxBodies == 0 || maxBodies > (1u << 22))
        return NULL;
    Context *c = calloc(1, sizeof(Context));
    if (!c)
        return NULL;
    c->slots = 1;
    while (c->slots < maxBodies * 2)
        c->slots *= 2;
    c->bodies = calloc(c->slots, sizeof(Body));
    if (!c->bodies) {
        free(c);
        return NULL;
    }
    initialize(&c->mutex);
    c->caller = thread_id();
    return c;
}

/* Mutations are caller-thread only, strictly outside PhysicsSystem_Update. */
EXPORT uint32_t KP_SetBody(Context *c, uint32_t id, const JPH_Shape *shape,
                           const Material *materials, uint32_t count) {
    Body *b = body(c, id);
    if (count > b->capacity) {
        Material *copy = realloc(b->materials, count * sizeof(Material));
        if (!copy)
            return 0;
        b->materials = copy;
        b->capacity = count;
    }
    if (count)
        memcpy(b->materials, materials, count * sizeof(Material));
    b->id = id;
    b->occupied = 1;
    b->shape = shape;
    b->count = count;
    return 1;
}

EXPORT void KP_RemoveBody(Context *c, uint32_t id) {
    Body *b = body(c, id);
    free(b->materials);
    memset(b, 0, sizeof(*b));
    /* Repair the probe cluster; body IDs include a generation, so slots are reusable. */
    uint32_t slot = (uint32_t)(b - c->bodies);
    for (slot = (slot + 1) & (c->slots - 1); c->bodies[slot].occupied;
         slot = (slot + 1) & (c->slots - 1)) {
        Body moved = c->bodies[slot];
        memset(&c->bodies[slot], 0, sizeof(Body));
        *body(c, moved.id) = moved;
    }
}

EXPORT uint32_t KP_Exclude(Context *c, uint32_t a, uint32_t b, uint32_t enabled) {
    for (size_t i = 0; i < c->excludedCount; ++i) {
        Pair p = c->excluded[i];
        if ((p.a == a && p.b == b) || (p.a == b && p.b == a)) {
            if (!enabled)
                c->excluded[i] = c->excluded[--c->excludedCount];
            return 1;
        }
    }
    if (!enabled)
        return 1;
    if (c->excludedCount == c->excludedCapacity) {
        size_t capacity = c->excludedCapacity ? c->excludedCapacity * 2 : 16;
        Pair *pairs = realloc(c->excluded, capacity * sizeof(Pair));
        if (!pairs)
            return 0;
        c->excluded = pairs;
        c->excludedCapacity = capacity;
    }
    c->excluded[c->excludedCount++] = (Pair){a, b};
    return 1;
}

EXPORT const Event *KP_Events(Context *c) {
    return c->events;
}
EXPORT size_t KP_Count(Context *c) {
    return c->count;
}
EXPORT uint32_t KP_Failed(Context *c) {
    return c->failed;
}
EXPORT void KP_Clear(Context *c) {
    c->count = 0;
}
EXPORT uint64_t KP_WorkerCallbacks(Context *c) {
    return c->workerCallbacks;
}
EXPORT uint64_t KP_CallerCallbacks(Context *c) {
    return c->callerCallbacks;
}
EXPORT void KP_Destroy(Context *c) {
    for (uint32_t i = 0; i < c->slots; ++i)
        free(c->bodies[i].materials);
    dispose(&c->mutex);
    free(c->bodies);
    free(c->excluded);
    free(c->events);
    free(c);
}
