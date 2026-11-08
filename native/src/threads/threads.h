/*
 * katsa_threads: worker threads with their own Lua state, message queues and shared memory.
 *
 * Every actor is one OS thread that owns one Lua state (LuaJIT states are independent, so workers
 * run truly in parallel). The library never links against Lua: the host hands over the few Lua C
 * API entry points it needs (kt_init), from `ffi.C` of the running process, so the same binary
 * works with the dev host (luajit) and the shipped host (which exports its embedded LuaJIT).
 *
 * Threads talk only through byte messages (copied; the Lua side serializes them) and through
 * shared blocks (raw memory with a reference count, read and written with plain FFI access plus
 * the atomics in shared.c). No Lua value ever crosses a thread boundary.
 *
 * Files:
 *   platform.c   mutexes, condition variables, threads, clocks and sleeping (Win32 / pthreads)
 *   queue.c      the message queue (a mutex-protected linked list with a condition variable)
 *   actor.c      actors: spawning, messaging, state, stopping and freeing
 *   shared.c     reference-counted shared blocks and int32 atomics
 *
 * Thread safety: every exported function may be called from any thread unless noted. Fields of
 * KActor that both sides touch are read and written with atomic operations (see actor.c).
 *
 * Compiler: the atomics use the GCC/Clang __atomic builtins (gcc, clang, llvm-mingw); MSVC is
 * not supported.
 *
 * Lua declarations: source/katsa/thread/binding.lua. Worker prelude: source/katsa/thread/worker.lua.
 */
#ifndef KATSA_THREADS_H
#define KATSA_THREADS_H

#include <stddef.h>
#include <stdint.h>

#include "common/export.h"

#if defined(_WIN32)
#include <windows.h>
typedef HANDLE KThread;
typedef CRITICAL_SECTION KMutex;
typedef CONDITION_VARIABLE KCond;
#else
#include <pthread.h>
typedef pthread_t KThread;
typedef pthread_mutex_t KMutex;
typedef pthread_cond_t KCond;
#endif

/* ---------------------------------------------------------------------------------------------- */
/* The Lua C API, supplied by the host. The layout is mirrored by ffi.cdef in binding.lua.        */
/* ---------------------------------------------------------------------------------------------- */

typedef struct KLuaApi {
    void* (*newstate)(void);                                    /* luaL_newstate */
    void (*openlibs)(void*);                                    /* luaL_openlibs */
    int (*loadbuffer)(void*, const char*, size_t, const char*); /* luaL_loadbuffer */
    int (*pcall)(void*, int, int, int);                         /* lua_pcall */
    const char* (*tolstring)(void*, int, size_t*);              /* lua_tolstring */
    void (*settop)(void*, int);                                 /* lua_settop */
    void (*close)(void*);                                       /* lua_close */
} KLuaApi;

/* ---------------------------------------------------------------------------------------------- */
/* platform.c                                                                                     */
/* ---------------------------------------------------------------------------------------------- */

void mutex_init(KMutex* mutex);
void mutex_destroy(KMutex* mutex);
void mutex_lock(KMutex* mutex);
void mutex_unlock(KMutex* mutex);

void cond_init(KCond* cond);
void cond_destroy(KCond* cond);
void cond_signal(KCond* cond);
/* Waits on `cond` with `mutex` held; timeoutMs < 0 waits without a limit. May return early
 * (spurious wakeup or timeout): the caller re-checks its condition. */
void cond_wait(KCond* cond, KMutex* mutex, int timeoutMs);

/* Starts `body(argument)` on a new thread with an 8 MB stack. Returns 0 on success. */
int thread_start(KThread* thread, void (*body)(void*), void* argument);
/* Waits for a finished or finishing thread and releases it. */
void thread_join(KThread thread);
/* Releases the handle of a thread that keeps running and will clean up after itself. */
void thread_detach(KThread thread);

/* Milliseconds from an arbitrary start, never going backwards (unlike the wall clock). */
uint64_t monotonic_ms(void);
void sleep_ms(int ms);

/* ---------------------------------------------------------------------------------------------- */
/* queue.c                                                                                        */
/* ---------------------------------------------------------------------------------------------- */

/* One message: a heap block holding the header and the bytes. The pointer to the header is the
 * handle Lua receives from kt_recv and returns with kt_release. */
typedef struct KMsg {
    struct KMsg* next;
    size_t length;
    unsigned char data[1]; /* `length` bytes (allocated past the end of the struct) */
} KMsg;

typedef struct KQueue {
    KMsg* head; /* oldest message */
    KMsg* tail; /* newest message */
    int count;
    KMutex mutex; /* guards head, tail and count */
    KCond cond;   /* signalled when a message arrives (and by kt_request_stop on the inbox) */
} KQueue;

void queue_init(KQueue* queue);
/* Frees the messages still queued and the synchronization objects. No thread may use it after. */
void queue_destroy(KQueue* queue);
/* Appends a message (ownership passes to the queue) and wakes one waiting receiver. */
void queue_push(KQueue* queue, KMsg* message);
/* Takes the oldest message, waiting up to timeoutMs when the queue is empty (0: do not wait,
 * < 0: no limit). `stop` (may be NULL) is an atomic flag: when it is set, the call does not
 * start waiting. Returns NULL when nothing arrived. */
KMsg* queue_pop(KQueue* queue, int timeoutMs, const int* stop);
int queue_count(KQueue* queue);

#endif
