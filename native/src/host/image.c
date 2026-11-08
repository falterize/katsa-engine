/*
 * The host's executable image on Windows, Linux and macOS: the file that carries the archive is
 * the running executable itself. (Android keeps the archive as an APK asset; see android.c.)
 */
#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L /* readlink */
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "host.h"

#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
#endif

void host_free_image(HostImage* image) {
    free(image->data);
    image->data = NULL;
    image->size = 0;
}

/* Reads an opened file whole into the image. Closes the file. */
static int read_whole(HostImage* image, FILE* file) {
    if (!file) {
        return 0;
    }
    long size = -1;
    if (fseek(file, 0, SEEK_END) == 0) {
        size = ftell(file);
    }
    if (size < 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
    image->size = (size_t)size;
    image->data = (unsigned char*)malloc(image->size ? image->size : 1);
    int ok = image->data && fread(image->data, 1, image->size, file) == image->size;
    fclose(file);
    if (!ok) {
        host_free_image(image);
    }
    return ok;
}

#if !defined(__ANDROID__)

int host_load_image(HostImage* image, const char* argv0) {
#if defined(_WIN32)
    /* The wide API, so any folder name works; Lua receives the path as UTF-8 like every other
     * path (katsa_fs_* expect UTF-8, and Native.loadFile loads DLLs from non-ASCII folders). */
    (void)argv0;
    wchar_t wide[4096];
    DWORD count = GetModuleFileNameW(NULL, wide, 4096);
    if (count == 0 || count >= 4096) {
        return 0; /* failed, or the path was truncated */
    }
    if (WideCharToMultiByte(CP_UTF8, 0, wide, -1, image->path, (int)sizeof image->path, NULL,
                            NULL)
        <= 0) {
        return 0;
    }
    return read_whole(image, _wfopen(wide, L"rb"));
#elif defined(__APPLE__)
    (void)argv0;
    uint32_t size = sizeof image->path;
    if (_NSGetExecutablePath(image->path, &size) != 0) {
        return 0;
    }
    return read_whole(image, fopen(image->path, "rb"));
#else
    ssize_t count = readlink("/proc/self/exe", image->path, sizeof image->path - 1);
    if (count > 0) {
        image->path[count] = '\0';
    } else {
        /* No /proc (some sandboxes): trust argv[0]. */
        strncpy(image->path, argv0, sizeof image->path - 1);
        image->path[sizeof image->path - 1] = '\0';
    }
    return read_whole(image, fopen(image->path, "rb"));
#endif
}

#else

/* Used by android.c once the archive is copied out of the APK. */
int host_read_image_file(HostImage* image) {
    return read_whole(image, fopen(image->path, "rb"));
}

#endif
