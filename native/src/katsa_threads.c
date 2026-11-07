/*
 * katsa_threads: worker threads with their own Lua state, message queues and shared memory.
 *
 * Every actor is one OS thread that owns one Lua state (LuaJIT states are independent, so workers
 * run truly in parallel). The library never links against Lua: the host hands over the few Lua C
 * API entry points it needs (kt_init) -- from `ffi.C` in the dev host, from the embedded LuaJIT in
 * the shipped host -- so the same binary works wherever the process exports them.
 *
 * Threads talk only through byte messages (copied; the Lua side serializes) and through shared
 * blocks (raw memory with a reference count, read and written with plain FFI access plus the
 * atomics below). No Lua value ever crosses a thread boundary.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#include <process.h>
#define KT_EXPORT __declspec(dllexport)
typedef HANDLE KThread;
typedef CRITICAL_SECTION KMutex;
typedef CONDITION_VARIABLE KCond;
#else
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#define KT_EXPORT __attribute__((visibility("default")))
typedef pthread_t KThread;
typedef pthread_mutex_t KMutex;
typedef pthread_cond_t KCond;
#endif

/* ---- Lua C API, supplied by the host ------------------------------------------------------ */

typedef struct KLuaApi {
    void* (*newstate)(void);
    void (*openlibs)(void*);
    int (*loadbuffer)(void*, const char*, size_t, const char*);
    int (*pcall)(void*, int, int, int);
    const char* (*tolstring)(void*, int, size_t*);
    void (*settop)(void*, int);
    void (*close)(void*);
} KLuaApi;

static KLuaApi lua;
static int lua_ready = 0;

/* ---- Portable primitives ------------------------------------------------------------------ */

static void mutex_init(KMutex* m) {
#if defined(_WIN32)
    InitializeCriticalSection(m);
#else
    pthread_mutex_init(m, NULL);
#endif
}

static void mutex_destroy(KMutex* m) {
#if defined(_WIN32)
    DeleteCriticalSection(m);
#else
    pthread_mutex_destroy(m);
#endif
}

static void mutex_lock(KMutex* m) {
#if defined(_WIN32)
    EnterCriticalSection(m);
#else
    pthread_mutex_lock(m);
#endif
}

static void mutex_unlock(KMutex* m) {
#if defined(_WIN32)
    LeaveCriticalSection(m);
#else
    pthread_mutex_unlock(m);
#endif
}

static void cond_init(KCond* c) {
#if defined(_WIN32)
    InitializeConditionVariable(c);
#else
    pthread_cond_init(c, NULL);
#endif
}

static void cond_destroy(KCond* c) {
#if defined(_WIN32)
    (void)c;
#else
    pthread_cond_destroy(c);
#endif
}

static void cond_signal(KCond* c) {
#if defined(_WIN32)
    WakeConditionVariable(c);
#else
    pthread_cond_signal(c);
#endif
}

/* Waits with the mutex held; timeoutMs < 0 waits forever. */
static void cond_wait(KCond* c, KMutex* m, int timeoutMs) {
#if defined(_WIN32)
    SleepConditionVariableCS(c, m, timeoutMs < 0 ? INFINITE : (DWORD)timeoutMs);
#else
    if (timeoutMs < 0) {
        pthread_cond_wait(c, m);
        return;
    }
    struct timespec t;
    clock_gettime(CLOCK_REALTIME, &t);
    t.tv_sec += timeoutMs / 1000;
    t.tv_nsec += (long)(timeoutMs % 1000) * 1000000L;
    if (t.tv_nsec >= 1000000000L) {
        t.tv_sec += 1;
        t.tv_nsec -= 1000000000L;
    }
    pthread_cond_timedwait(c, m, &t);
#endif
}

/* ---- Messages and actors ------------------------------------------------------------------ */

typedef struct KMsg {
    struct KMsg* next;
    size_t length;
    unsigned char data[1];
} KMsg;

typedef struct KQueue {
    KMsg* head;
    KMsg* tail;
    int count;
    KMutex mutex;
    KCond cond;
} KQueue;

enum { KT_STARTING = 0, KT_RUNNING = 1, KT_FINISHED = 2, KT_FAILED = 3 };

typedef struct KActor {
    KThread thread;
    KQueue inbox;  /* main -> worker */
    KQueue outbox; /* worker -> main */
    volatile int state;
    volatile int stop;
    volatile int claim; /* whoever finishes second (thread end, kt_destroy) frees the actor */
    volatile int exited;
    char error[1024];
    char* bootstrap;
    char name[64];
} KActor;

static void queue_init(KQueue* q) {
    q->head = q->tail = NULL;
    q->count = 0;
    mutex_init(&q->mutex);
    cond_init(&q->cond);
}

static void queue_clear(KQueue* q) {
    KMsg* m = q->head;
    while (m) {
        KMsg* next = m->next;
        free(m);
        m = next;
    }
    q->head = q->tail = NULL;
    q->count = 0;
}

static void queue_destroy(KQueue* q) {
    queue_clear(q);
    mutex_destroy(&q->mutex);
    cond_destroy(&q->cond);
}

static void queue_push(KQueue* q, KMsg* m) {
    m->next = NULL;
    mutex_lock(&q->mutex);
    if (q->tail) {
        q->tail->next = m;
    } else {
        q->head = m;
    }
    q->tail = m;
    q->count += 1;
    cond_signal(&q->cond);
    mutex_unlock(&q->mutex);
}

static KMsg* queue_pop(KQueue* q, int timeoutMs, volatile int* stop) {
    mutex_lock(&q->mutex);
    if (!q->head && timeoutMs != 0 && !(stop && *stop)) {
        cond_wait(&q->cond, &q->mutex, timeoutMs);
    }
    KMsg* m = q->head;
    if (m) {
        q->head = m->next;
        if (!q->head) {
            q->tail = NULL;
        }
        q->count -= 1;
    }
    mutex_unlock(&q->mutex);
    return m;
}

static void actor_free(KActor* a) {
    queue_destroy(&a->inbox);
    queue_destroy(&a->outbox);
    free(a->bootstrap);
    free(a);
}

static void actor_run(KActor* a) {
    void* L = lua.newstate();
    if (!L) {
        snprintf(a->error, sizeof a->error, "cannot create a Lua state");
        a->state = KT_FAILED;
        return;
    }
    lua.openlibs(L);
    a->state = KT_RUNNING;
    int status = lua.loadbuffer(L, a->bootstrap, strlen(a->bootstrap), "=actor");
    if (status == 0) {
        status = lua.pcall(L, 0, 0, 0);
    }
    if (status != 0) {
        const char* message = lua.tolstring(L, -1, NULL);
        snprintf(a->error, sizeof a->error, "%s", message ? message : "unknown error");
        a->state = KT_FAILED;
    } else {
        a->state = KT_FINISHED;
    }
    lua.settop(L, 0);
    lua.close(L);
}

#if defined(_WIN32)
static unsigned __stdcall actor_main(void* arg)
#else
static void* actor_main(void* arg)
#endif
{
    KActor* a = (KActor*)arg;
    actor_run(a);
    a->exited = 1;
    if (__atomic_exchange_n(&a->claim, 1, __ATOMIC_SEQ_CST) == 1) {
        /* The owner already let go: nobody else will free this actor. */
        actor_free(a);
    }
#if defined(_WIN32)
    return 0;
#else
    return NULL;
#endif
}

/* ---- Exported API ------------------------------------------------------------------------- */

KT_EXPORT int kt_init(const KLuaApi* api) {
    if (!api || !api->newstate || !api->openlibs || !api->loadbuffer || !api->pcall ||
        !api->tolstring || !api->settop || !api->close) {
        return 0;
    }
    lua = *api;
    lua_ready = 1;
    return 1;
}

KT_EXPORT int kt_cpu_count(void) {
#if defined(_WIN32)
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return (int)info.dwNumberOfProcessors;
#else
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (int)n : 1;
#endif
}

/* `bootstrap` is the Lua chunk the worker runs; it is copied. */
KT_EXPORT KActor* kt_spawn(const char* name, const char* bootstrap, size_t length) {
    if (!lua_ready) {
        return NULL;
    }
    KActor* a = (KActor*)calloc(1, sizeof(KActor));
    if (!a) {
        return NULL;
    }
    queue_init(&a->inbox);
    queue_init(&a->outbox);
    snprintf(a->name, sizeof a->name, "%s", name ? name : "actor");
    /* The chunk starts with the actor's own address, which the worker's prelude needs. */
    char prefix[64];
    int prefixLength = snprintf(prefix, sizeof prefix, "KATSA_ACTOR=%.0f\n", (double)(uintptr_t)a);
    a->bootstrap = (char*)malloc((size_t)prefixLength + length + 1);
    if (!a->bootstrap) {
        actor_free(a);
        return NULL;
    }
    memcpy(a->bootstrap, prefix, (size_t)prefixLength);
    memcpy(a->bootstrap + prefixLength, bootstrap, length);
    a->bootstrap[(size_t)prefixLength + length] = 0;
#if defined(_WIN32)
    a->thread = (HANDLE)_beginthreadex(NULL, 8u << 20, actor_main, a, 0, NULL);
    if (!a->thread) {
#else
    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    pthread_attr_setstacksize(&attributes, 8u << 20);
    int failed = pthread_create(&a->thread, &attributes, actor_main, a);
    pthread_attr_destroy(&attributes);
    if (failed) {
#endif
        actor_free(a);
        return NULL;
    }
    return a;
}

/* toWorker = 1: main -> worker inbox; 0: worker -> main outbox. */
KT_EXPORT int kt_send(KActor* a, int toWorker, const void* data, size_t length) {
    KMsg* m = (KMsg*)malloc(sizeof(KMsg) + length);
    if (!m) {
        return 0;
    }
    m->length = length;
    if (length) {
        memcpy(m->data, data, length);
    }
    queue_push(toWorker ? &a->inbox : &a->outbox, m);
    return 1;
}

/* Pops one message from the worker's inbox (fromInbox = 1) or the main outbox (0). Waits up to
 * timeoutMs (< 0 forever, 0 not at all). Returns the message handle, or NULL when none arrived or
 * the actor was asked to stop. The data stays valid until kt_release. */
KT_EXPORT void* kt_recv(KActor* a, int fromInbox, int timeoutMs, const void** data, size_t* length) {
    KMsg* m = queue_pop(fromInbox ? &a->inbox : &a->outbox, timeoutMs, fromInbox ? &a->stop : NULL);
    if (!m) {
        return NULL;
    }
    *data = m->data;
    *length = m->length;
    return m;
}

KT_EXPORT void kt_release(void* message) {
    free(message);
}

KT_EXPORT int kt_pending(KActor* a, int inbox) {
    KQueue* q = inbox ? &a->inbox : &a->outbox;
    mutex_lock(&q->mutex);
    int n = q->count;
    mutex_unlock(&q->mutex);
    return n;
}

KT_EXPORT int kt_state(KActor* a) {
    return a->state;
}

KT_EXPORT int kt_exited(KActor* a) {
    return a->exited;
}

KT_EXPORT const char* kt_error(KActor* a) {
    return a->error;
}

KT_EXPORT int kt_stopped(KActor* a) {
    return a->stop;
}

/* Cooperative stop: the worker sees kt_stopped() and its blocking receive returns. */
KT_EXPORT void kt_request_stop(KActor* a) {
    a->stop = 1;
    mutex_lock(&a->inbox.mutex);
    cond_signal(&a->inbox.cond);
    mutex_unlock(&a->inbox.mutex);
}

/* Waits for the thread to end; returns 1 when it did. */
KT_EXPORT int kt_join(KActor* a, int timeoutMs) {
    int waited = 0;
    while (!a->exited) {
        if (timeoutMs >= 0 && waited >= timeoutMs) {
            return 0;
        }
#if defined(_WIN32)
        Sleep(1);
#else
        struct timespec t = {0, 1000000L};
        nanosleep(&t, NULL);
#endif
        waited += 1;
    }
    return 1;
}

/* Releases the actor. A thread that is still running frees the memory itself when it ends. */
KT_EXPORT void kt_destroy(KActor* a) {
    kt_request_stop(a);
    if (__atomic_exchange_n(&a->claim, 1, __ATOMIC_SEQ_CST) == 1) {
        /* The thread has finished already. */
#if defined(_WIN32)
        WaitForSingleObject(a->thread, INFINITE);
        CloseHandle(a->thread);
#else
        pthread_join(a->thread, NULL);
#endif
        actor_free(a);
        return;
    }
#if defined(_WIN32)
    CloseHandle(a->thread);
#else
    pthread_detach(a->thread);
#endif
}

/* ---- Shared memory ------------------------------------------------------------------------ */

typedef struct KShared {
    volatile int32_t refs;
    int32_t pad;
    uint64_t size;
} KShared; /* 16 bytes: the payload that follows stays 16-byte aligned */

KT_EXPORT void* kt_shared_new(size_t size) {
    KShared* block = (KShared*)calloc(1, sizeof(KShared) + size + 16);
    if (!block) {
        return NULL;
    }
    block->refs = 1;
    block->size = size;
    return block;
}

KT_EXPORT void* kt_shared_data(void* handle) {
    return (unsigned char*)handle + sizeof(KShared);
}

KT_EXPORT size_t kt_shared_size(void* handle) {
    return (size_t)((KShared*)handle)->size;
}

KT_EXPORT void kt_shared_retain(void* handle) {
    __atomic_add_fetch(&((KShared*)handle)->refs, 1, __ATOMIC_SEQ_CST);
}

/* Returns the references left; the block is freed at zero. */
KT_EXPORT int kt_shared_release(void* handle) {
    int left = __atomic_sub_fetch(&((KShared*)handle)->refs, 1, __ATOMIC_SEQ_CST);
    if (left == 0) {
        free(handle);
    }
    return left;
}

KT_EXPORT int kt_shared_refs(void* handle) {
    return __atomic_load_n(&((KShared*)handle)->refs, __ATOMIC_SEQ_CST);
}

/* Atomics on int32 slots of shared memory (sequentially consistent). */
KT_EXPORT int32_t kt_atomic_load(int32_t* p) {
    return __atomic_load_n(p, __ATOMIC_SEQ_CST);
}

KT_EXPORT void kt_atomic_store(int32_t* p, int32_t v) {
    __atomic_store_n(p, v, __ATOMIC_SEQ_CST);
}

KT_EXPORT int32_t kt_atomic_add(int32_t* p, int32_t v) {
    return __atomic_add_fetch(p, v, __ATOMIC_SEQ_CST);
}

KT_EXPORT int kt_atomic_cas(int32_t* p, int32_t expected, int32_t desired) {
    return __atomic_compare_exchange_n(p, &expected, desired, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}

KT_EXPORT void kt_sleep(int ms) {
#if defined(_WIN32)
    Sleep((DWORD)ms);
#else
    struct timespec t = {ms / 1000, (long)(ms % 1000) * 1000000L};
    nanosleep(&t, NULL);
#endif
}
