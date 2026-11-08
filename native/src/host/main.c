/*
 * The host's entry point: reads the executable image, creates the Lua state and runs
 * __katsa/boot.lua from the appended archive (see host.h for the file layout).
 *
 * Lua receives one global, `katsa_host`:
 *
 *     katsa_host.exe    UTF-8 path of the file that holds the archive
 *     katsa_host.args   command-line arguments after the program name, { [1] = ..., ... }
 *     katsa_host.read   function(name) -> contents of a STORE entry, or nil
 *
 * boot.lua may return an integer, which becomes the process exit status.
 *
 * The Lua C API of this executable is also what katsa_threads uses to create worker states, so
 * the build exports it (-rdynamic / -Wl,-export_dynamic; see tools/native/build.py).
 */
#include <stdio.h>
#include <stdlib.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <luajit.h>

#include "host.h"

#if defined(__ANDROID__)
#include <SDL.h> /* renames main to SDL_main, which SDLActivity calls */
#endif

#define BOOT_ENTRY "__katsa/boot.lua"

/* The image lives as long as the Lua state: katsa_host.read returns copies of its entries. */
static HostImage image;

#if !defined(__ANDROID__)
void host_report(const char* message, const char* detail) {
    fprintf(stderr, "%s%s\n", message, detail ? detail : "");
}
#endif

/* katsa_host.read(name) */
static int lua_host_read(lua_State* L) {
    size_t length;
    const unsigned char* data = host_archive_find(&image, luaL_checkstring(L, 1), &length);
    if (data) {
        lua_pushlstring(L, (const char*)data, length);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

/* Creates the `katsa_host` global. */
static void publish_host_table(lua_State* L, int argc, char** argv) {
    lua_newtable(L);

    lua_pushstring(L, image.path);
    lua_setfield(L, -2, "exe");

    lua_pushcfunction(L, lua_host_read);
    lua_setfield(L, -2, "read");

    lua_newtable(L);
    for (int i = 1; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i);
    }
    lua_setfield(L, -2, "args");

    lua_setglobal(L, "katsa_host");
}

/* Runs boot.lua. Returns the process exit status. */
static int run_boot(lua_State* L) {
    size_t length;
    const unsigned char* boot = host_archive_find(&image, BOOT_ENTRY, &length);
    if (!boot) {
        host_report("katsa: runtime not found (missing " BOOT_ENTRY ") in ", image.path);
        return 1;
    }
    /* "=" makes Lua use the name as is in error messages instead of [string "..."]. */
    if (luaL_loadbuffer(L, (const char*)boot, length, "=" BOOT_ENTRY) != 0
        || lua_pcall(L, 0, 1, 0) != 0) {
        host_report("katsa: ", lua_tostring(L, -1));
        return 1;
    }
    return lua_isnumber(L, -1) ? (int)lua_tointeger(L, -1) : 0;
}

int main(int argc, char** argv) {
#if defined(__ANDROID__)
    host_android_redirect_output();
#endif
    if (!host_load_image(&image, argv[0])) {
        host_report("katsa: cannot read own executable", NULL);
        return 1;
    }
    lua_State* L = luaL_newstate();
    if (!L) {
        host_report("katsa: cannot create the Lua state", NULL);
        host_free_image(&image);
        return 1;
    }
    luaL_openlibs(L);
    publish_host_table(L, argc, argv);
    int status = run_boot(L);
    lua_close(L);
    host_free_image(&image);
    return status;
}
