-- FFI declarations of katsa_threads (see native/src/katsa_threads.c) and the loader.
--
-- The native library does not link Lua. It is handed the Lua C API entry points of the running
-- process (kt_init): the dev host's luajit executable exports them, and the shipped host exports
-- its embedded LuaJIT the same way (`-rdynamic`; on Windows the host must export them too).
local ffi = require('ffi')
local Native = require('source.katsa.core.native')

local CDEF = [[
typedef struct KActor KActor;
typedef struct KLuaApi {
    void* (*newstate)(void);
    void (*openlibs)(void*);
    int (*loadbuffer)(void*, const char*, size_t, const char*);
    int (*pcall)(void*, int, int, int);
    const char* (*tolstring)(void*, int, size_t*);
    void (*settop)(void*, int);
    void (*close)(void*);
} KLuaApi;
int kt_init(const KLuaApi* api);
int kt_cpu_count(void);
KActor* kt_spawn(const char* name, const char* bootstrap, size_t length);
int kt_send(KActor* actor, int toWorker, const void* data, size_t length);
void* kt_recv(KActor* actor, int fromInbox, int timeoutMs, const void** data, size_t* length);
void kt_release(void* message);
int kt_pending(KActor* actor, int inbox);
int kt_state(KActor* actor);
int kt_exited(KActor* actor);
const char* kt_error(KActor* actor);
int kt_stopped(KActor* actor);
void kt_request_stop(KActor* actor);
int kt_join(KActor* actor, int timeoutMs);
void kt_destroy(KActor* actor);
void* kt_shared_new(size_t size);
void* kt_shared_data(void* handle);
size_t kt_shared_size(void* handle);
void kt_shared_retain(void* handle);
int kt_shared_release(void* handle);
int kt_shared_refs(void* handle);
int32_t kt_atomic_load(int32_t* p);
void kt_atomic_store(int32_t* p, int32_t v);
int32_t kt_atomic_add(int32_t* p, int32_t v);
int kt_atomic_cas(int32_t* p, int32_t expected, int32_t desired);
void kt_sleep(int ms);
]]

local Binding = { cdef = CDEF }

local library, failure

-- Returns the library, or nil plus the reason (missing binary, or a process that does not export
-- the Lua C API).
function Binding.load()
    if library then
        return library
    end
    if failure then
        return nil, failure
    end
    local lib, message = Native.load('Threads')
    if not lib then
        failure = message
        return nil, failure
    end
    pcall(ffi.cdef, CDEF) -- already declared when this module was loaded twice under two names
    local ok, api = pcall(function()
        local C = ffi.C
        local table = ffi.new('KLuaApi')
        local names = {
            newstate = 'luaL_newstate',
            openlibs = 'luaL_openlibs',
            loadbuffer = 'luaL_loadbuffer',
            pcall = 'lua_pcall',
            tolstring = 'lua_tolstring',
            settop = 'lua_settop',
            close = 'lua_close',
        }
        pcall(ffi.cdef, [[
        void* luaL_newstate(void);
        void luaL_openlibs(void*);
        int luaL_loadbuffer(void*, const char*, size_t, const char*);
        int lua_pcall(void*, int, int, int);
        const char* lua_tolstring(void*, int, size_t*);
        void lua_settop(void*, int);
        void lua_close(void*);
        ]])
        for field, name in pairs(names) do
            table[field] = C[name]
        end
        return table
    end)
    if not ok or lib.kt_init(api) == 0 then
        failure = 'The process does not export the Lua C API needed for worker threads: '
            .. tostring(api)
        return nil, failure
    end
    library = lib
    Binding.api = api -- keeps the function table alive for the native side
    return library
end

return Binding
