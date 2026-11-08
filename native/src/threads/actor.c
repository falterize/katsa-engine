/*
 * katsa_threads / actor: one worker thread with its own Lua state and two message queues.
 *
 * Lifetime. Two parties hold an actor: the owner (Lua on the main thread, until kt_destroy) and
 * the worker thread (until its Lua chunk returns). Whoever lets go second frees the memory. Each
 * party marks its exit by atomically exchanging `claim` to 1; the one that reads back 1 was
 * second:
 *
 *   worker ends first   owner's kt_destroy reads 1: joins the (finished) thread and frees
 *   owner lets go first worker reads 1 when its chunk returns: frees; the owner had detached it
 *
 * Shared fields. `state`, `stop`, `exited` and `claim` are written by one thread and read by the
 * other, so they are accessed only with __atomic operations. Release stores pair with acquire
 * loads, which also publishes what was written before them: `error` is complete before `state`
 * becomes KT_FAILED or `exited` becomes 1.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "threads.h"

/* kt_state values. Lua: source/katsa/thread/init.lua (STATES). */
enum { KT_STARTING = 0, KT_RUNNING = 1, KT_FINISHED = 2, KT_FAILED = 3 };

typedef struct KActor {
    KThread thread;
    KQueue inbox;   /* main -> worker */
    KQueue outbox;  /* worker -> main */
    int state;      /* KT_*, written by the worker */
    int stop;       /* 1 once the owner asked the worker to stop */
    int claim;      /* lifetime hand-off, see the file comment */
    int exited;     /* 1 once the worker thread is done with Lua */
    char error[1024];
    char* bootstrap; /* the Lua chunk the worker runs, NUL terminated */
    char name[64];
} KActor;

static KLuaApi lua;
static int lua_ready = 0;

static void actor_free(KActor* actor) {
    queue_destroy(&actor->inbox);
    queue_destroy(&actor->outbox);
    free(actor->bootstrap);
    free(actor);
}

static void set_state(KActor* actor, int state) {
    __atomic_store_n(&actor->state, state, __ATOMIC_RELEASE);
}

/* Runs the bootstrap chunk in a fresh Lua state and records how it ended. */
static void actor_run(KActor* actor) {
    void* L = lua.newstate();
    if (!L) {
        snprintf(actor->error, sizeof actor->error, "cannot create a Lua state");
        set_state(actor, KT_FAILED);
        return;
    }
    lua.openlibs(L);
    set_state(actor, KT_RUNNING);
    int status = lua.loadbuffer(L, actor->bootstrap, strlen(actor->bootstrap), "=actor");
    if (status == 0) {
        status = lua.pcall(L, 0, 0, 0);
    }
    if (status != 0) {
        const char* message = lua.tolstring(L, -1, NULL);
        snprintf(actor->error, sizeof actor->error, "%s", message ? message : "unknown error");
        set_state(actor, KT_FAILED);
    } else {
        set_state(actor, KT_FINISHED);
    }
    lua.settop(L, 0);
    lua.close(L);
}

/* The worker thread's body. */
static void actor_main(void* argument) {
    KActor* actor = (KActor*)argument;
    actor_run(actor);
    __atomic_store_n(&actor->exited, 1, __ATOMIC_RELEASE);
    if (__atomic_exchange_n(&actor->claim, 1, __ATOMIC_ACQ_REL) == 1) {
        /* The owner already let go and detached this thread: nobody else will free the actor. */
        actor_free(actor);
    }
}

/* ---------------------------------------------------------------------------------------------- */
/* Setup                                                                                          */
/* ---------------------------------------------------------------------------------------------- */

/* Stores the Lua C API of the running process. Returns 1, or 0 when an entry is missing (then
 * kt_spawn keeps failing). Call once from the main thread before the first kt_spawn. */
KATSA_EXPORT int kt_init(const KLuaApi* api) {
    if (!api || !api->newstate || !api->openlibs || !api->loadbuffer || !api->pcall
        || !api->tolstring || !api->settop || !api->close) {
        return 0;
    }
    lua = *api;
    lua_ready = 1;
    return 1;
}

/*
 * Starts a worker thread running `bootstrap` (`length` bytes of Lua source, copied). `name` is
 * kept for debugging. Returns the actor, or NULL when kt_init was not called or the thread could
 * not start.
 *
 * The chunk is prefixed with `KATSA_ACTOR=<address>`, the actor's own address, which the worker
 * prelude casts back to a KActor* for kt_send / kt_recv. The address is written as a Lua number;
 * a double holds integers up to 2^53 exactly, and user-space addresses on every supported 64-bit
 * system stay below 2^48.
 */
KATSA_EXPORT KActor* kt_spawn(const char* name, const char* bootstrap, size_t length) {
    if (!lua_ready) {
        return NULL;
    }
    KActor* actor = (KActor*)calloc(1, sizeof(KActor));
    if (!actor) {
        return NULL;
    }
    queue_init(&actor->inbox);
    queue_init(&actor->outbox);
    snprintf(actor->name, sizeof actor->name, "%s", name ? name : "actor");

    char prefix[64];
    int prefix_length =
        snprintf(prefix, sizeof prefix, "KATSA_ACTOR=%.0f\n", (double)(uintptr_t)actor);
    actor->bootstrap = (char*)malloc((size_t)prefix_length + length + 1);
    if (!actor->bootstrap) {
        actor_free(actor);
        return NULL;
    }
    memcpy(actor->bootstrap, prefix, (size_t)prefix_length);
    memcpy(actor->bootstrap + prefix_length, bootstrap, length);
    actor->bootstrap[(size_t)prefix_length + length] = '\0';

    if (thread_start(&actor->thread, actor_main, actor) != 0) {
        actor_free(actor);
        return NULL;
    }
    return actor;
}

/* ---------------------------------------------------------------------------------------------- */
/* Messages                                                                                       */
/* ---------------------------------------------------------------------------------------------- */

/* Queues a copy of `data`: into the worker's inbox when `toWorker` is non-zero (called by the
 * owner), otherwise into the outbox (called by the worker). Returns 1, or 0 when out of memory. */
KATSA_EXPORT int kt_send(KActor* actor, int toWorker, const void* data, size_t length) {
    KMsg* message = (KMsg*)malloc(sizeof(KMsg) + length);
    if (!message) {
        return 0;
    }
    message->length = length;
    if (length) {
        memcpy(message->data, data, length);
    }
    queue_push(toWorker ? &actor->inbox : &actor->outbox, message);
    return 1;
}

/*
 * Takes one message from the inbox (`fromInbox` non-zero, called by the worker) or the outbox
 * (called by the owner), waiting up to timeoutMs (< 0: no limit, 0: not at all). A worker waiting
 * on its inbox also returns when the owner asks it to stop.
 *
 * Returns a message handle and sets *data / *length, or returns NULL when nothing arrived. The
 * bytes stay valid until the handle is passed to kt_release.
 */
KATSA_EXPORT void* kt_recv(KActor* actor, int fromInbox, int timeoutMs, const void** data,
                           size_t* length) {
    KQueue* queue = fromInbox ? &actor->inbox : &actor->outbox;
    KMsg* message = queue_pop(queue, timeoutMs, fromInbox ? &actor->stop : NULL);
    if (!message) {
        return NULL;
    }
    *data = message->data;
    *length = message->length;
    return message;
}

KATSA_EXPORT void kt_release(void* message) {
    free(message);
}

/* Messages waiting in the inbox (`inbox` non-zero) or the outbox. */
KATSA_EXPORT int kt_pending(KActor* actor, int inbox) {
    return queue_count(inbox ? &actor->inbox : &actor->outbox);
}

/* ---------------------------------------------------------------------------------------------- */
/* State                                                                                          */
/* ---------------------------------------------------------------------------------------------- */

KATSA_EXPORT int kt_state(KActor* actor) {
    return __atomic_load_n(&actor->state, __ATOMIC_ACQUIRE);
}

KATSA_EXPORT int kt_exited(KActor* actor) {
    return __atomic_load_n(&actor->exited, __ATOMIC_ACQUIRE);
}

/* The error message of a failed actor ("" otherwise). Read it after kt_state returned KT_FAILED;
 * the text lives as long as the actor. */
KATSA_EXPORT const char* kt_error(KActor* actor) {
    return actor->error;
}

KATSA_EXPORT int kt_stopped(KActor* actor) {
    return __atomic_load_n(&actor->stop, __ATOMIC_ACQUIRE);
}

/* ---------------------------------------------------------------------------------------------- */
/* Stopping and freeing                                                                           */
/* ---------------------------------------------------------------------------------------------- */

/* Cooperative stop: kt_stopped() turns true in the worker and a blocking kt_recv on the inbox
 * returns. The worker's Lua code decides when to finish. */
KATSA_EXPORT void kt_request_stop(KActor* actor) {
    __atomic_store_n(&actor->stop, 1, __ATOMIC_RELEASE);
    /* Signal under the mutex so a receiver between its stop check and its wait cannot miss it
     * (see queue_pop). */
    mutex_lock(&actor->inbox.mutex);
    cond_signal(&actor->inbox.cond);
    mutex_unlock(&actor->inbox.mutex);
}

/* Waits up to timeoutMs (< 0: no limit) for the worker to finish its Lua chunk. Returns 1 when
 * it has, 0 on timeout. Polls every millisecond. */
KATSA_EXPORT int kt_join(KActor* actor, int timeoutMs) {
    uint64_t deadline = monotonic_ms() + (uint64_t)(timeoutMs > 0 ? timeoutMs : 0);
    while (!kt_exited(actor)) {
        if (timeoutMs >= 0 && monotonic_ms() >= deadline) {
            return 0;
        }
        sleep_ms(1);
    }
    return 1;
}

/* Lets go of the actor (asks it to stop first). The owner must not use the handle afterwards. A
 * worker that is still running frees the actor itself when its chunk returns. */
KATSA_EXPORT void kt_destroy(KActor* actor) {
    kt_request_stop(actor);
    /* Read the handle before letting go: once `claim` is exchanged the worker may free the actor
     * at any moment, so `actor` must not be touched on the detach path below. (Reading it after
     * the exchange was a use-after-free found with ThreadSanitizer.) */
    KThread thread = actor->thread;
    if (__atomic_exchange_n(&actor->claim, 1, __ATOMIC_ACQ_REL) == 1) {
        /* The worker is done (it may still be returning from actor_main): wait and free. */
        thread_join(thread);
        actor_free(actor);
        return;
    }
    thread_detach(thread);
}
