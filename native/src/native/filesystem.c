/*
 * katsa_native / filesystem: UTF-8 file access for katsa.filesystem.
 *
 * LuaJIT's io library opens files through the C runtime's narrow API, which on Windows reads paths
 * in the ANSI code page, so any non-ASCII path (a user name such as "Админ") fails. These functions
 * take UTF-8 everywhere and convert to UTF-16 on Windows.
 *
 * Conventions for every function here:
 *   - paths are UTF-8, either separator is accepted on Windows;
 *   - integer results are 0 on success and -1 on failure unless documented otherwise;
 *   - buffers returned to Lua come from malloc and are released with katsa_free.
 */
#if !defined(_WIN32)
/* fseeko/ftello/readlink are POSIX, and a 64-bit off_t keeps large files readable on 32-bit
 * targets (armeabi-v7a). Both must be defined before the first system header. */
#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#endif

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common/export.h"

#if defined(_WIN32)
#include <windows.h>
#else
#include <dirent.h>
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
#endif

enum { KIND_MISSING = 0, KIND_FILE = 1, KIND_DIRECTORY = 2 };

/* ---------------------------------------------------------------------------------------------- */
/* Platform helpers                                                                               */
/* ---------------------------------------------------------------------------------------------- */

#if defined(_WIN32)

/* UTF-8 -> newly allocated UTF-16 string, or NULL. The caller frees it. */
static wchar_t* widen(const char* utf8) {
    int count = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (count <= 0) {
        return NULL;
    }
    wchar_t* wide = (wchar_t*)malloc((size_t)count * sizeof(wchar_t));
    if (wide) {
        MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, count);
    }
    return wide;
}

/* UTF-16 -> UTF-8 into `out`. Returns the bytes written including the terminating NUL, or 0. */
static int narrow(const wchar_t* wide, char* out, int capacity) {
    return WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, capacity, NULL, NULL);
}

/* Seconds between 1601-01-01 (FILETIME epoch) and 1970-01-01 (Unix epoch). */
#define UNIX_EPOCH_IN_FILETIME_SECONDS 11644473600LL
#define FILETIME_TICKS_PER_SECOND 10000000ULL

#endif

/* fopen with a UTF-8 path. `mode` is a plain ASCII mode such as "rb". */
static FILE* open_file(const char* path, const char* mode) {
#if defined(_WIN32)
    wchar_t wide_mode[8];
    size_t i = 0;
    for (; mode[i] != '\0' && i + 1 < sizeof wide_mode / sizeof wide_mode[0]; i++) {
        wide_mode[i] = (wchar_t)mode[i];
    }
    wide_mode[i] = L'\0';
    wchar_t* wide = widen(path);
    if (!wide) {
        return NULL;
    }
    FILE* file = _wfopen(wide, wide_mode);
    free(wide);
    return file;
#else
    return fopen(path, mode);
#endif
}

/* 64-bit seek and tell: `long` is 32 bits on Windows, so plain fseek/ftell stop at 2 GB. */
static int seek_to(FILE* file, int64_t offset, int origin) {
#if defined(_WIN32)
    return _fseeki64(file, offset, origin);
#else
    return fseeko(file, (off_t)offset, origin);
#endif
}

static int64_t tell(FILE* file) {
#if defined(_WIN32)
    return _ftelli64(file);
#else
    return (int64_t)ftello(file);
#endif
}

/* Creates one directory whose parent exists. An existing directory counts as success. */
static int make_directory(const char* path) {
#if defined(_WIN32)
    wchar_t* wide = widen(path);
    if (!wide) {
        return -1;
    }
    int ok = CreateDirectoryW(wide, NULL) || GetLastError() == ERROR_ALREADY_EXISTS;
    free(wide);
    return ok ? 0 : -1;
#else
    return (mkdir(path, 0777) == 0 || errno == EEXIST) ? 0 : -1;
#endif
}

static int is_separator(char c) {
    return c == '/' || c == '\\';
}

/* ---------------------------------------------------------------------------------------------- */
/* Exported API                                                                                   */
/* ---------------------------------------------------------------------------------------------- */

/*
 * What is at `path`: 0 nothing, 1 a file, 2 a directory.
 * `size` (bytes) and `modified` (Unix seconds) are optional out parameters.
 */
KATSA_EXPORT int katsa_fs_stat(const char* path, int64_t* size, int64_t* modified) {
#if defined(_WIN32)
    wchar_t* wide = widen(path);
    if (!wide) {
        return KIND_MISSING;
    }
    WIN32_FILE_ATTRIBUTE_DATA data;
    BOOL found = GetFileAttributesExW(wide, GetFileExInfoStandard, &data);
    free(wide);
    if (!found) {
        return KIND_MISSING;
    }
    if (size) {
        *size = ((int64_t)data.nFileSizeHigh << 32) | data.nFileSizeLow;
    }
    if (modified) {
        uint64_t ticks = ((uint64_t)data.ftLastWriteTime.dwHighDateTime << 32)
                         | data.ftLastWriteTime.dwLowDateTime;
        *modified = (int64_t)(ticks / FILETIME_TICKS_PER_SECOND) - UNIX_EPOCH_IN_FILETIME_SECONDS;
    }
    return (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? KIND_DIRECTORY : KIND_FILE;
#else
    struct stat info;
    if (stat(path, &info) != 0) {
        return KIND_MISSING;
    }
    if (size) {
        *size = (int64_t)info.st_size;
    }
    if (modified) {
        *modified = (int64_t)info.st_mtime;
    }
    return S_ISDIR(info.st_mode) ? KIND_DIRECTORY : KIND_FILE;
#endif
}

/* Creates a directory and every missing parent (like `mkdir -p`). */
KATSA_EXPORT int katsa_fs_mkdir(const char* path) {
    size_t length = strlen(path);
    char* prefix = (char*)malloc(length + 1);
    if (!prefix) {
        return -1;
    }
    memcpy(prefix, path, length + 1);
    /* Create each parent by cutting the path at every separator in turn. A drive root such as
     * "C:" (separator at index 2) is never created. Failures here are ignored on purpose: the
     * final make_directory reports whether the whole path exists. */
    for (size_t i = 1; i < length; i++) {
        if (!is_separator(prefix[i])) {
            continue;
        }
        char separator = prefix[i];
        prefix[i] = '\0';
        int drive_root = i == 2 && prefix[1] == ':';
        if (!drive_root && katsa_fs_stat(prefix, NULL, NULL) != KIND_DIRECTORY) {
            make_directory(prefix);
        }
        prefix[i] = separator;
    }
    int result = katsa_fs_stat(path, NULL, NULL) == KIND_DIRECTORY ? 0 : make_directory(prefix);
    free(prefix);
    return result;
}

/* Removes a file or an empty directory. */
KATSA_EXPORT int katsa_fs_remove(const char* path) {
#if defined(_WIN32)
    wchar_t* wide = widen(path);
    if (!wide) {
        return -1;
    }
    int is_directory = katsa_fs_stat(path, NULL, NULL) == KIND_DIRECTORY;
    BOOL removed = is_directory ? RemoveDirectoryW(wide) : DeleteFileW(wide);
    free(wide);
    return removed ? 0 : -1;
#else
    return remove(path) == 0 ? 0 : -1;
#endif
}

/*
 * Lists the entries of a directory (without "." and "..") as NUL-terminated UTF-8 names packed
 * one after another into `buffer`.
 *
 * Returns the number of bytes the full listing needs, or -1 when the directory cannot be read.
 * Names that do not fit into `capacity` are skipped but still counted, so a result larger than
 * `capacity` means "call again with a buffer of that size"; the listing is never cut silently.
 */
KATSA_EXPORT int64_t katsa_fs_list(const char* path, char* buffer, int64_t capacity) {
    int64_t used = 0;
#if defined(_WIN32)
    size_t length = strlen(path);
    char* pattern = (char*)malloc(length + 3);
    if (!pattern) {
        return -1;
    }
    memcpy(pattern, path, length);
    memcpy(pattern + length, "\\*", 3);
    wchar_t* wide = widen(pattern);
    free(pattern);
    if (!wide) {
        return -1;
    }
    WIN32_FIND_DATAW entry;
    HANDLE search = FindFirstFileW(wide, &entry);
    free(wide);
    if (search == INVALID_HANDLE_VALUE) {
        return -1;
    }
    do {
        if (wcscmp(entry.cFileName, L".") == 0 || wcscmp(entry.cFileName, L"..") == 0) {
            continue;
        }
        char name[1024];
        int count = narrow(entry.cFileName, name, (int)sizeof name); /* includes the NUL */
        if (count <= 0) {
            continue;
        }
        if (used + count <= capacity) {
            memcpy(buffer + used, name, (size_t)count);
        }
        used += count;
    } while (FindNextFileW(search, &entry));
    FindClose(search);
#else
    DIR* directory = opendir(path);
    if (!directory) {
        return -1;
    }
    struct dirent* entry;
    while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        int64_t count = (int64_t)strlen(entry->d_name) + 1; /* includes the NUL */
        if (used + count <= capacity) {
            memcpy(buffer + used, entry->d_name, (size_t)count);
        }
        used += count;
    }
    closedir(directory);
#endif
    return used;
}

/* Reads a whole file. Returns a malloc'd buffer (release with katsa_free) and sets *size, or NULL. */
KATSA_EXPORT uint8_t* katsa_fs_read(const char* path, int64_t* size) {
    FILE* file = open_file(path, "rb");
    if (!file) {
        return NULL;
    }
    int64_t length = -1;
    if (seek_to(file, 0, SEEK_END) == 0) {
        length = tell(file);
    }
    if (length < 0 || seek_to(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    /* malloc(0) may return NULL, so an empty file still gets a one-byte buffer. */
    uint8_t* data = (uint8_t*)malloc(length > 0 ? (size_t)length : 1);
    if (!data) {
        fclose(file);
        return NULL;
    }
    size_t read = length > 0 ? fread(data, 1, (size_t)length, file) : 0;
    fclose(file);
    if (read != (size_t)length) {
        free(data);
        return NULL;
    }
    *size = length;
    return data;
}

/* Reads up to `length` bytes at `offset` into `buffer`. Returns the bytes read, or -1. */
KATSA_EXPORT int64_t katsa_fs_read_range(const char* path, int64_t offset, uint8_t* buffer,
                                         int64_t length) {
    FILE* file = open_file(path, "rb");
    if (!file) {
        return -1;
    }
    if (seek_to(file, offset, SEEK_SET) != 0) {
        fclose(file);
        return -1;
    }
    size_t read = fread(buffer, 1, (size_t)length, file);
    fclose(file);
    return (int64_t)read;
}

/* Writes `size` bytes, replacing the file or appending to it when `append` is non-zero. */
KATSA_EXPORT int katsa_fs_write(const char* path, const uint8_t* data, int64_t size, int append) {
    FILE* file = open_file(path, append ? "ab" : "wb");
    if (!file) {
        return -1;
    }
    size_t written = size > 0 ? fwrite(data, 1, (size_t)size, file) : 0;
    /* fclose flushes; a full disk may only be reported here. */
    int closed = fclose(file);
    return (written == (size_t)size && closed == 0) ? 0 : -1;
}

/* Absolute UTF-8 path of the running executable. Returns its length in bytes, or -1. */
KATSA_EXPORT int katsa_exe_path(char* buffer, int capacity) {
#if defined(_WIN32)
    wchar_t wide[4096];
    DWORD count = GetModuleFileNameW(NULL, wide, 4096);
    if (count == 0 || count >= 4096) {
        return -1; /* failed, or the path was truncated */
    }
    int written = narrow(wide, buffer, capacity);
    return written > 0 ? written - 1 : -1;
#elif defined(__APPLE__)
    uint32_t size = (uint32_t)capacity;
    if (_NSGetExecutablePath(buffer, &size) != 0) {
        return -1; /* buffer too small */
    }
    return (int)strlen(buffer);
#else
    ssize_t count = readlink("/proc/self/exe", buffer, (size_t)capacity - 1);
    if (count < 0) {
        return -1;
    }
    buffer[count] = '\0'; /* readlink does not terminate */
    return (int)count;
#endif
}
