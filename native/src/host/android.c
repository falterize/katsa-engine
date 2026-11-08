/*
 * The host on Android, where it is built as libmain.so (android/app/src/main/cpp/CMakeLists.txt).
 *
 * SDLActivity loads libmain.so and calls SDL_main (SDL.h renames main). The game archive is the
 * APK asset ASSET_NAME; the Lua runtime reads archives by path, so the asset is copied once to
 * internal storage and that copy becomes the image. stdout/stderr are forwarded to logcat.
 */
#if defined(__ANDROID__)

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <android/log.h>
#include <pthread.h>
#include <unistd.h>

#include <SDL.h>

#include "host.h"

#define ASSET_NAME "game.katsa"
#define LOG_TAG "katsa"

/* Large enough to copy and compare the asset quickly, small enough for the stack. */
#define CHUNK_SIZE 65536

void host_report(const char* message, const char* detail) {
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "%s%s", message, detail ? detail : "");
}

/* ---------------------------------------------------------------------------------------------- */
/* stdout / stderr -> logcat                                                                      */
/* ---------------------------------------------------------------------------------------------- */

/* Thread body: reads the pipe and writes every complete line (or every 1023 bytes of a longer
 * one) to logcat. Runs for the lifetime of the process. */
static void* forward_log(void* argument) {
    int pipe_read = (int)(intptr_t)argument;
    char line[1024];
    size_t used = 0;
    char c;
    while (read(pipe_read, &c, 1) == 1) {
        if (c == '\n' || used == sizeof line - 1) {
            line[used] = '\0';
            __android_log_write(ANDROID_LOG_INFO, LOG_TAG, line);
            used = 0;
        } else {
            line[used++] = c;
        }
    }
    return NULL;
}

void host_android_redirect_output(void) {
    int fds[2];
    if (pipe(fds) != 0) {
        return; /* output stays invisible, the game still runs */
    }
    dup2(fds[1], STDOUT_FILENO);
    dup2(fds[1], STDERR_FILENO);
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    pthread_t thread;
    pthread_create(&thread, NULL, forward_log, (void*)(intptr_t)fds[0]);
    pthread_detach(thread);
}

/* ---------------------------------------------------------------------------------------------- */
/* The archive: APK asset -> internal storage                                                     */
/* ---------------------------------------------------------------------------------------------- */

/* True when the copy at `path` has exactly the asset's bytes. Streams both files in chunks
 * instead of loading them, so a large game does not cost twice its size in memory. */
static int asset_matches(const char* path) {
    static unsigned char asset_chunk[CHUNK_SIZE], copy_chunk[CHUNK_SIZE];
    FILE* copy = fopen(path, "rb");
    SDL_RWops* asset = SDL_RWFromFile(ASSET_NAME, "rb");
    int same = copy && asset;
    while (same) {
        size_t count = SDL_RWread(asset, asset_chunk, 1, CHUNK_SIZE);
        if (fread(copy_chunk, 1, count, copy) != count
            || memcmp(asset_chunk, copy_chunk, count) != 0) {
            same = 0;
        }
        if (count < CHUNK_SIZE) {
            /* End of the asset: the copy must end here too. */
            same = same && fread(copy_chunk, 1, 1, copy) == 0;
            break;
        }
    }
    if (copy) {
        fclose(copy);
    }
    if (asset) {
        SDL_RWclose(asset);
    }
    return same;
}

static int copy_asset(const char* path) {
    static unsigned char chunk[CHUNK_SIZE];
    SDL_RWops* asset = SDL_RWFromFile(ASSET_NAME, "rb");
    FILE* copy = fopen(path, "wb");
    int ok = asset && copy;
    size_t count;
    while (ok && (count = SDL_RWread(asset, chunk, 1, CHUNK_SIZE)) > 0) {
        if (fwrite(chunk, 1, count, copy) != count) {
            ok = 0;
        }
    }
    if (copy && fclose(copy) != 0) {
        ok = 0; /* a full disk may only show up when the copy is flushed */
    }
    if (asset) {
        SDL_RWclose(asset);
    }
    return ok;
}

int host_load_image(HostImage* image, const char* argv0) {
    (void)argv0;
    const char* storage = SDL_AndroidGetInternalStoragePath();
    if (!storage) {
        host_report("katsa: no internal storage", NULL);
        return 0;
    }
    snprintf(image->path, sizeof image->path, "%s/" ASSET_NAME, storage);
    /* An unchanged copy is kept, which makes every start after the first one cheap. */
    if (!asset_matches(image->path) && !copy_asset(image->path)) {
        host_report("katsa: cannot copy the game archive from assets/" ASSET_NAME, NULL);
        return 0;
    }
    return host_read_image_file(image);
}

#endif
