/*
 * Stress test for katsa_threads under ThreadSanitizer / AddressSanitizer (Linux).
 *
 * Spawns many actors, sends them messages, reads some echoes and destroys every actor at a random
 * moment (before, during or after its exit) to exercise the lifetime hand-off in actor.c. Every
 * 17th actor fails on purpose; the report must show all of those failures.
 *
 *     sh validation/native/threadsStress.sh          # builds with TSan and ASan, runs both
 *
 * Expected: "races=0" for the TSan run, no "ERROR" for the ASan run, failures=N/N for both.
 * Requires gcc with libtsan/libasan and a static LuaJIT (LUAJIT_PREFIX, default /usr/local).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <time.h>

typedef struct KActor KActor;
typedef struct KLuaApi {
    void* (*newstate)(void); void (*openlibs)(void*);
    int (*loadbuffer)(void*, const char*, size_t, const char*);
    int (*pcall)(void*, int, int, int); const char* (*tolstring)(void*, int, size_t*);
    void (*settop)(void*, int); void (*close)(void*);
} KLuaApi;
int kt_init(const KLuaApi*); KActor* kt_spawn(const char*, const char*, size_t);
int kt_send(KActor*, int, const void*, size_t);
void* kt_recv(KActor*, int, int, const void**, size_t*); void kt_release(void*);
int kt_state(KActor*); int kt_exited(KActor*); const char* kt_error(KActor*);
void kt_request_stop(KActor*); int kt_join(KActor*, int); void kt_destroy(KActor*);
void* kt_shared_new(size_t); void* kt_shared_data(void*); void kt_shared_retain(void*);
int kt_shared_release(void*); int32_t kt_atomic_add(int32_t*, int32_t);

/* Worker: echo every inbox message back to the outbox until stopped. Uses ffi on the exported
 * kt_* symbols of this executable. */
static const char* WORKER =
"local ffi = require('ffi')\n"
"ffi.cdef[[typedef struct KActor KActor;\n"
"int kt_send(KActor*, int, const void*, size_t);\n"
"void* kt_recv(KActor*, int, int, const void**, size_t*); void kt_release(void*);\n"
"int kt_stopped(KActor*); int32_t kt_atomic_add(int32_t*, int32_t);]]\n"
"local C = ffi.C\n"
"local self = ffi.cast('KActor*', KATSA_ACTOR)\n"
"local data, len = ffi.new('const void*[1]'), ffi.new('size_t[1]')\n"
"local counter = ffi.cast('int32_t*', COUNTER)\n"
"if FAIL then error('planned failure') end\n"
"while C.kt_stopped(self) == 0 do\n"
"  local m = C.kt_recv(self, 1, 5, data, len)\n"
"  if m ~= nil then\n"
"    C.kt_atomic_add(counter, 1)\n"
"    C.kt_send(self, 0, data[0], len[0]); C.kt_release(m)\n"
"  end\n"
"end\n";

int main(int argc, char** argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 200;
    KLuaApi api = { (void*(*)(void))luaL_newstate, (void(*)(void*))luaL_openlibs,
        (int(*)(void*,const char*,size_t,const char*))luaL_loadbuffer,
        (int(*)(void*,int,int,int))lua_pcall, (const char*(*)(void*,int,size_t*))lua_tolstring,
        (void(*)(void*,int))lua_settop, (void(*)(void*))lua_close };
    if (!kt_init(&api)) { puts("init failed"); return 1; }
    srand(12345);
    void* shared = kt_shared_new(64);
    int32_t* counter = (int32_t*)kt_shared_data(shared);
    long sent = 0, echoed = 0; int failed_seen = 0;
    for (int r = 0; r < rounds; r++) {
        int fail = (r % 17) == 0;
        char chunk[4096];
        snprintf(chunk, sizeof chunk, "COUNTER=%.0f FAIL=%s\n%s", (double)(uintptr_t)counter,
                 fail ? "true" : "false", WORKER);
        KActor* a = kt_spawn("stress", chunk, strlen(chunk));
        if (!a) { puts("spawn failed"); return 1; }
        int n = rand() % 20;
        for (int i = 0; i < n; i++) { kt_send(a, 1, &i, sizeof i); sent++; }
        /* Read some echoes, then destroy at a random point: before, during or after the worker's
         * exit, to exercise both sides of the claim hand-off. */
        int reads = rand() % (n + 1);
        for (int i = 0; i < reads; i++) {
            const void* d; size_t l;
            void* m = kt_recv(a, 0, 50, &d, &l);
            if (m) { echoed++; kt_release(m); }
        }
        int mode = rand() % 3;
        if (mode == 1) { kt_request_stop(a); kt_join(a, 1000); }
        if (mode == 2) { struct timespec t = {0, (rand() % 2000) * 1000L}; nanosleep(&t, NULL); }
        if (fail) {
            kt_join(a, 2000);
            if (kt_state(a) == 3 && strstr(kt_error(a), "planned failure")) failed_seen++;
        }
        kt_destroy(a);
    }
    struct timespec t = {0, 300 * 1000000L}; nanosleep(&t, NULL); /* let detached workers end */
    printf("rounds=%d sent=%ld echoed=%ld handled=%d failures=%d/%d\n", rounds, sent, echoed,
           kt_atomic_add(counter, 0), failed_seen, (rounds + 16) / 17);
    kt_shared_release(shared);
    return 0;
}
