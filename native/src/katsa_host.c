/* katsa host: LuaJIT + the appended ZIP archive. Becomes katsa.exe on Windows.
 *
 * Layout of a runnable file:  [host binary][ZIP archive].  The ZIP holds the Lua runtime
 * (STORE entries under source/katsa/ and __katsa/boot.lua) and, when the game is fused in,
 * the game files. The host only reads STORE entries; everything else is done in Lua.
 * Lua gets one global, `katsa_host`: { exe = path, args = {...}, read = function(name) }.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <luajit.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#ifdef __ANDROID__
/* Android: this file becomes libmain.so. SDL's SDLActivity calls SDL_main (SDL.h renames main), the
 * game archive is an APK asset that is copied once to internal storage, and stdout/stderr go to logcat. */
#include <pthread.h>
#include <android/log.h>
#include <SDL.h>
#endif
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#endif

static char exe_path[4096];
static unsigned char *file_data; /* whole executable image */
static size_t file_size;

static void report(const char *message, const char *detail)
{
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_ERROR, "katsa", "%s%s", message, detail ? detail : "");
#else
    fprintf(stderr, "%s%s\n", message, detail ? detail : "");
#endif
}

static uint32_t u16(const unsigned char *p) { return p[0] | (p[1] << 8); }
static uint32_t u32(const unsigned char *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }

#ifdef __ANDROID__
#define ASSET_NAME "game.katsa"

/* Lua's print and io.stderr write to the pipe; one thread forwards complete lines to logcat. */
static void *forward_log(void *arg)
{
    int fd = (int)(intptr_t)arg;
    char line[1024];
    size_t used = 0;
    char c;
    while (read(fd, &c, 1) == 1) {
        if (c == '\n' || used == sizeof line - 1) {
            line[used] = 0;
            __android_log_write(ANDROID_LOG_INFO, "katsa", line);
            used = 0;
        } else {
            line[used++] = c;
        }
    }
    return NULL;
}

static void redirect_output(void)
{
    int fds[2];
    pthread_t thread;
    if (pipe(fds) != 0) return;
    dup2(fds[1], 1);
    dup2(fds[1], 2);
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    pthread_create(&thread, NULL, forward_log, (void *)(intptr_t)fds[0]);
    pthread_detach(thread);
}

/* Compares the asset with the copy on disk without loading either into memory. */
static int asset_matches(const char *path)
{
    FILE *copy = fopen(path, "rb");
    SDL_RWops *asset = SDL_RWFromFile(ASSET_NAME, "rb");
    unsigned char a[65536], b[65536];
    int same = copy && asset;
    while (same) {
        size_t n = SDL_RWread(asset, a, 1, sizeof a);
        if (fread(b, 1, n, copy) != n || memcmp(a, b, n) != 0) same = 0;
        if (n < sizeof a) {
            same = same && fread(b, 1, 1, copy) == 0;
            break;
        }
    }
    if (copy) fclose(copy);
    if (asset) SDL_RWclose(asset);
    return same;
}

/* The runtime reads the archive by path, so the APK asset is copied to internal storage first;
 * an unchanged copy is kept, which makes later starts cheap. */
static int find_exe(char *argv0)
{
    const char *dir = SDL_AndroidGetInternalStoragePath();
    (void)argv0;
    if (!dir) { report("katsa: no internal storage", NULL); return 0; }
    snprintf(exe_path, sizeof exe_path, "%s/" ASSET_NAME, dir);
    if (asset_matches(exe_path)) return 1;

    SDL_RWops *asset = SDL_RWFromFile(ASSET_NAME, "rb");
    FILE *copy = fopen(exe_path, "wb");
    unsigned char chunk[65536];
    size_t n;
    int ok = asset && copy;
    while (ok && (n = SDL_RWread(asset, chunk, 1, sizeof chunk)) > 0) {
        if (fwrite(chunk, 1, n, copy) != n) ok = 0;
    }
    if (copy && fclose(copy) != 0) ok = 0;
    if (asset) SDL_RWclose(asset);
    if (!ok) report("katsa: cannot copy the game archive from assets/" ASSET_NAME, NULL);
    return ok;
}
#else
static int find_exe(char *argv0)
{
#ifdef _WIN32
    DWORD n = GetModuleFileNameA(NULL, exe_path, sizeof exe_path);
    return n > 0 && n < sizeof exe_path;
#elif defined(__APPLE__)
    uint32_t size = sizeof exe_path;
    return _NSGetExecutablePath(exe_path, &size) == 0;
#else
    ssize_t n = readlink("/proc/self/exe", exe_path, sizeof exe_path - 1);
    if (n > 0) { exe_path[n] = 0; return 1; }
    strncpy(exe_path, argv0, sizeof exe_path - 1);
    return 1;
#endif
}
#endif

static int load_image(void)
{
    FILE *f = fopen(exe_path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    file_size = (size_t)ftell(f);
    fseek(f, 0, SEEK_SET);
    file_data = malloc(file_size ? file_size : 1);
    if (!file_data || fread(file_data, 1, file_size, f) != file_size) { fclose(f); return 0; }
    fclose(f);
    return 1;
}

/* Finds a STORE entry; returns pointer + length or NULL. */
static const unsigned char *zip_find(const char *name, size_t *length)
{
    if (file_size < 22) return NULL;
    size_t eocd = file_size - 22;
    for (;; eocd--) {
        if (u32(file_data + eocd) == 0x06054b50) break;
        if (eocd == 0 || file_size - eocd > 22 + 65535) return NULL;
    }
    uint32_t count = u16(file_data + eocd + 10);
    uint32_t dir_size = u32(file_data + eocd + 12), dir_off = u32(file_data + eocd + 16);
    size_t base = eocd - dir_size - dir_off; /* offset of the archive start inside the file */
    const unsigned char *p = file_data + base + dir_off;
    size_t want = strlen(name);
    for (uint32_t i = 0; i < count; i++) {
        if (u32(p) != 0x02014b50) return NULL;
        uint32_t method = u16(p + 10), csize = u32(p + 20), usize = u32(p + 24);
        uint32_t nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32), loff = u32(p + 42);
        if (nlen == want && memcmp(p + 46, name, nlen) == 0) {
            if (method != 0 || csize != usize) return NULL;
            const unsigned char *local = file_data + base + loff;
            if (u32(local) != 0x04034b50) return NULL;
            *length = usize;
            return local + 30 + u16(local + 26) + u16(local + 28);
        }
        p += 46 + nlen + elen + clen;
    }
    return NULL;
}

static int host_read(lua_State *L)
{
    size_t length;
    const unsigned char *data = zip_find(luaL_checkstring(L, 1), &length);
    if (!data) { lua_pushnil(L); return 1; }
    lua_pushlstring(L, (const char *)data, length);
    return 1;
}

int main(int argc, char **argv)
{
#ifdef __ANDROID__
    redirect_output();
#endif
    if (!find_exe(argv[0]) || !load_image()) {
        report("katsa: cannot read own executable", NULL);
        return 1;
    }
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    lua_newtable(L);
    lua_pushstring(L, exe_path); lua_setfield(L, -2, "exe");
    lua_pushcfunction(L, host_read); lua_setfield(L, -2, "read");
    lua_newtable(L);
    for (int i = 1; i < argc; i++) { lua_pushstring(L, argv[i]); lua_rawseti(L, -2, i); }
    lua_setfield(L, -2, "args");
    lua_setglobal(L, "katsa_host");

    size_t length;
    const unsigned char *boot = zip_find("__katsa/boot.lua", &length);
    if (!boot) {
        report("katsa: runtime not found (missing __katsa/boot.lua) in ", exe_path);
        return 1;
    }
    int status = 0;
    if (luaL_loadbuffer(L, (const char *)boot, length, "=__katsa/boot.lua") || lua_pcall(L, 0, 1, 0)) {
        report("katsa: ", lua_tostring(L, -1));
        status = 1;
    } else if (lua_isnumber(L, -1)) {
        status = (int)lua_tointeger(L, -1);
    }
    lua_close(L);
    free(file_data);
    return status;
}
