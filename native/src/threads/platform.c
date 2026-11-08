/*
 * katsa_threads / platform: the few OS primitives the library needs, over Win32 or pthreads.
 */
#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L /* clock_gettime, nanosleep, sysconf */
#endif

#include <stdlib.h>

#include "threads.h"

#if defined(_WIN32)
#include <process.h>
#else
#include <time.h>
#include <unistd.h>
#endif

/* Worker Lua states run deep recursion (parsers, serializers); 8 MB matches a main thread. */
#define THREAD_STACK_SIZE (8u << 20)

/* ---------------------------------------------------------------------------------------------- */
/* Mutexes and condition variables                                                                */
/* ---------------------------------------------------------------------------------------------- */

void mutex_init(KMutex* mutex) {
#if defined(_WIN32)
    InitializeCriticalSection(mutex);
#else
    pthread_mutex_init(mutex, NULL);
#endif
}

void mutex_destroy(KMutex* mutex) {
#if defined(_WIN32)
    DeleteCriticalSection(mutex);
#else
    pthread_mutex_destroy(mutex);
#endif
}

void mutex_lock(KMutex* mutex) {
#if defined(_WIN32)
    EnterCriticalSection(mutex);
#else
    pthread_mutex_lock(mutex);
#endif
}

void mutex_unlock(KMutex* mutex) {
#if defined(_WIN32)
    LeaveCriticalSection(mutex);
#else
    pthread_mutex_unlock(mutex);
#endif
}

void cond_init(KCond* cond) {
#if defined(_WIN32)
    InitializeConditionVariable(cond);
#else
    pthread_cond_init(cond, NULL);
#endif
}

void cond_destroy(KCond* cond) {
#if defined(_WIN32)
    (void)cond; /* Win32 condition variables need no cleanup */
#else
    pthread_cond_destroy(cond);
#endif
}

void cond_signal(KCond* cond) {
#if defined(_WIN32)
    WakeConditionVariable(cond);
#else
    pthread_cond_signal(cond);
#endif
}

void cond_wait(KCond* cond, KMutex* mutex, int timeoutMs) {
#if defined(_WIN32)
    SleepConditionVariableCS(cond, mutex, timeoutMs < 0 ? INFINITE : (DWORD)timeoutMs);
#else
    if (timeoutMs < 0) {
        pthread_cond_wait(cond, mutex);
        return;
    }
    /* pthread_cond_timedwait takes an absolute wall-clock deadline (CLOCK_REALTIME; macOS has no
     * monotonic variant). A clock change can shorten or stretch this wait, which is harmless:
     * callers treat an early return like a timeout and try again. */
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += timeoutMs / 1000;
    deadline.tv_nsec += (long)(timeoutMs % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }
    pthread_cond_timedwait(cond, mutex, &deadline);
#endif
}

/* ---------------------------------------------------------------------------------------------- */
/* Threads                                                                                        */
/* ---------------------------------------------------------------------------------------------- */

/* The OS entry points have different signatures; both forward to the portable body. */
typedef struct ThreadStart {
    void (*body)(void*);
    void* argument;
} ThreadStart;

#if defined(_WIN32)
static unsigned __stdcall thread_entry(void* start_pointer) {
#else
static void* thread_entry(void* start_pointer) {
#endif
    ThreadStart start = *(ThreadStart*)start_pointer;
    free(start_pointer);
    start.body(start.argument);
#if defined(_WIN32)
    return 0;
#else
    return NULL;
#endif
}

int thread_start(KThread* thread, void (*body)(void*), void* argument) {
    ThreadStart* start = (ThreadStart*)malloc(sizeof(ThreadStart));
    if (!start) {
        return -1;
    }
    start->body = body;
    start->argument = argument;
#if defined(_WIN32)
    /* _beginthreadex rather than CreateThread so the C runtime is set up for the thread. */
    *thread = (HANDLE)_beginthreadex(NULL, THREAD_STACK_SIZE, thread_entry, start, 0, NULL);
    if (!*thread) {
        free(start);
        return -1;
    }
    return 0;
#else
    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    pthread_attr_setstacksize(&attributes, THREAD_STACK_SIZE);
    int failed = pthread_create(thread, &attributes, thread_entry, start);
    pthread_attr_destroy(&attributes);
    if (failed) {
        free(start);
        return -1;
    }
    return 0;
#endif
}

void thread_join(KThread thread) {
#if defined(_WIN32)
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
#else
    pthread_join(thread, NULL);
#endif
}

void thread_detach(KThread thread) {
#if defined(_WIN32)
    CloseHandle(thread); /* the thread keeps running; only our handle goes away */
#else
    pthread_detach(thread);
#endif
}

/* ---------------------------------------------------------------------------------------------- */
/* Time                                                                                           */
/* ---------------------------------------------------------------------------------------------- */

uint64_t monotonic_ms(void) {
#if defined(_WIN32)
    return (uint64_t)GetTickCount64();
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000u + (uint64_t)(now.tv_nsec / 1000000L);
#endif
}

void sleep_ms(int ms) {
#if defined(_WIN32)
    Sleep((DWORD)ms);
#else
    struct timespec duration = { ms / 1000, (long)(ms % 1000) * 1000000L };
    nanosleep(&duration, NULL);
#endif
}

/* ---------------------------------------------------------------------------------------------- */
/* Exported helpers                                                                               */
/* ---------------------------------------------------------------------------------------------- */

/* Logical processors available to the process (at least 1). */
KATSA_EXPORT int kt_cpu_count(void) {
#if defined(_WIN32)
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return (int)info.dwNumberOfProcessors;
#else
    long count = sysconf(_SC_NPROCESSORS_ONLN);
    return count > 0 ? (int)count : 1;
#endif
}

KATSA_EXPORT void kt_sleep(int ms) {
    sleep_ms(ms);
}
