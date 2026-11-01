/*
 * katsa_native: the small C layer under the katsa runtime.
 *
 * It exists only where LuaJIT's FFI cannot be portable: UTF-8 file access on Windows, directory
 * listing, and image/audio codecs (stb). Everything else in katsa is Lua over SDL2/OpenGL/OpenAL.
 * Build for every target with tools/native/build.py (see docs/guides/katsa/building.md).
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#if defined(_WIN32)
#define KATSA_EXPORT __declspec(dllexport)
#include <windows.h>
#include <direct.h>
#else
#define KATSA_EXPORT __attribute__((visibility("default")))
#include <dirent.h>
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
#endif

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#define STBI_FAILURE_USERMSG
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO
#include "stb_image_write.h"
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

KATSA_EXPORT int katsa_version(void) { return 1; }

KATSA_EXPORT void katsa_free(void* pointer) { free(pointer); }

/* ---------------------------------------------------------------- filesystem */

#if defined(_WIN32)
static wchar_t* widen(const char* utf8) {
    int count = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (count <= 0) return NULL;
    wchar_t* wide = (wchar_t*)malloc((size_t)count * sizeof(wchar_t));
    if (!wide) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, count);
    return wide;
}
static int narrow(const wchar_t* wide, char* out, int capacity) {
    return WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, capacity, NULL, NULL);
}
#endif

/* Returns 0 when missing, 1 for a file, 2 for a directory. Size and modification time (seconds) are optional. */
KATSA_EXPORT int katsa_fs_stat(const char* path, int64_t* size, int64_t* modified) {
#if defined(_WIN32)
    wchar_t* wide = widen(path);
    if (!wide) return 0;
    WIN32_FILE_ATTRIBUTE_DATA data;
    BOOL ok = GetFileAttributesExW(wide, GetFileExInfoStandard, &data);
    free(wide);
    if (!ok) return 0;
    if (size) *size = ((int64_t)data.nFileSizeHigh << 32) | data.nFileSizeLow;
    if (modified) {
        uint64_t ticks = ((uint64_t)data.ftLastWriteTime.dwHighDateTime << 32) | data.ftLastWriteTime.dwLowDateTime;
        *modified = (int64_t)(ticks / 10000000ULL) - 11644473600LL;
    }
    return (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 2 : 1;
#else
    struct stat info;
    if (stat(path, &info) != 0) return 0;
    if (size) *size = (int64_t)info.st_size;
    if (modified) *modified = (int64_t)info.st_mtime;
    return S_ISDIR(info.st_mode) ? 2 : 1;
#endif
}

static int make_one(const char* path) {
#if defined(_WIN32)
    wchar_t* wide = widen(path);
    if (!wide) return -1;
    int ok = CreateDirectoryW(wide, NULL) || GetLastError() == ERROR_ALREADY_EXISTS;
    free(wide);
    return ok ? 0 : -1;
#else
    return (mkdir(path, 0777) == 0 || errno == EEXIST) ? 0 : -1;
#endif
}

/* Creates a directory and every missing parent. Returns 0 on success. */
KATSA_EXPORT int katsa_fs_mkdir(const char* path) {
    size_t length = strlen(path);
    char* copy = (char*)malloc(length + 1);
    if (!copy) return -1;
    memcpy(copy, path, length + 1);
    for (size_t i = 1; i < length; i++) {
        if (copy[i] == '/' || copy[i] == '\\') {
            char saved = copy[i];
            copy[i] = '\0';
            if (!(i == 2 && copy[1] == ':') && katsa_fs_stat(copy, NULL, NULL) != 2) make_one(copy);
            copy[i] = saved;
        }
    }
    int result = katsa_fs_stat(path, NULL, NULL) == 2 ? 0 : make_one(copy);
    free(copy);
    return result;
}

/* Removes a file or an empty directory. Returns 0 on success. */
KATSA_EXPORT int katsa_fs_remove(const char* path) {
#if defined(_WIN32)
    wchar_t* wide = widen(path);
    if (!wide) return -1;
    int kind = katsa_fs_stat(path, NULL, NULL);
    int ok = kind == 2 ? RemoveDirectoryW(wide) : DeleteFileW(wide);
    free(wide);
    return ok ? 0 : -1;
#else
    return remove(path) == 0 ? 0 : -1;
#endif
}

/* Lists directory entries as NUL-separated UTF-8 names (without . and ..). Returns the number of
 * bytes needed; when it exceeds `capacity` nothing is truncated silently and the caller retries. */
KATSA_EXPORT int64_t katsa_fs_list(const char* path, char* buffer, int64_t capacity) {
    int64_t used = 0;
#if defined(_WIN32)
    size_t length = strlen(path);
    char* pattern = (char*)malloc(length + 3);
    if (!pattern) return -1;
    memcpy(pattern, path, length);
    pattern[length] = '\\'; pattern[length + 1] = '*'; pattern[length + 2] = '\0';
    wchar_t* wide = widen(pattern);
    free(pattern);
    if (!wide) return -1;
    WIN32_FIND_DATAW entry;
    HANDLE handle = FindFirstFileW(wide, &entry);
    free(wide);
    if (handle == INVALID_HANDLE_VALUE) return -1;
    do {
        if (wcscmp(entry.cFileName, L".") == 0 || wcscmp(entry.cFileName, L"..") == 0) continue;
        char name[1024];
        int count = narrow(entry.cFileName, name, sizeof name);
        if (count <= 0) continue;
        if (used + count <= capacity) memcpy(buffer + used, name, (size_t)count);
        used += count;
    } while (FindNextFileW(handle, &entry));
    FindClose(handle);
#else
    DIR* directory = opendir(path);
    if (!directory) return -1;
    struct dirent* entry;
    while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        int64_t count = (int64_t)strlen(entry->d_name) + 1;
        if (used + count <= capacity) memcpy(buffer + used, entry->d_name, (size_t)count);
        used += count;
    }
    closedir(directory);
#endif
    return used;
}

/* Reads a whole file into malloc memory (release with katsa_free). Returns NULL on failure. */
KATSA_EXPORT uint8_t* katsa_fs_read(const char* path, int64_t* size) {
#if defined(_WIN32)
    wchar_t* wide = widen(path);
    if (!wide) return NULL;
    FILE* file = _wfopen(wide, L"rb");
    free(wide);
#else
    FILE* file = fopen(path, "rb");
#endif
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    if (length < 0) { fclose(file); return NULL; }
    uint8_t* data = (uint8_t*)malloc(length > 0 ? (size_t)length : 1);
    if (!data) { fclose(file); return NULL; }
    size_t got = length > 0 ? fread(data, 1, (size_t)length, file) : 0;
    fclose(file);
    if (got != (size_t)length) { free(data); return NULL; }
    *size = length;
    return data;
}

/* Reads `length` bytes at `offset` into `buffer`. Returns the number of bytes read, or -1. */
KATSA_EXPORT int64_t katsa_fs_read_range(const char* path, int64_t offset, uint8_t* buffer, int64_t length) {
#if defined(_WIN32)
    wchar_t* wide = widen(path);
    if (!wide) return -1;
    FILE* file = _wfopen(wide, L"rb");
    free(wide);
#else
    FILE* file = fopen(path, "rb");
#endif
    if (!file) return -1;
#if defined(_WIN32)
    if (_fseeki64(file, offset, SEEK_SET) != 0) { fclose(file); return -1; }
#else
    if (fseeko(file, (off_t)offset, SEEK_SET) != 0) { fclose(file); return -1; }
#endif
    size_t got = fread(buffer, 1, (size_t)length, file);
    fclose(file);
    return (int64_t)got;
}

/* Writes (or appends) a whole buffer. Returns 0 on success. */
KATSA_EXPORT int katsa_fs_write(const char* path, const uint8_t* data, int64_t size, int append) {
#if defined(_WIN32)
    wchar_t* wide = widen(path);
    if (!wide) return -1;
    FILE* file = _wfopen(wide, append ? L"ab" : L"wb");
    free(wide);
#else
    FILE* file = fopen(path, append ? "ab" : "wb");
#endif
    if (!file) return -1;
    size_t wrote = size > 0 ? fwrite(data, 1, (size_t)size, file) : 0;
    int closed = fclose(file);
    return (wrote == (size_t)size && closed == 0) ? 0 : -1;
}

/* Absolute path of the running executable (UTF-8). Returns the length or -1. */
KATSA_EXPORT int katsa_exe_path(char* buffer, int capacity) {
#if defined(_WIN32)
    wchar_t wide[4096];
    DWORD count = GetModuleFileNameW(NULL, wide, 4096);
    if (count == 0 || count >= 4096) return -1;
    int written = narrow(wide, buffer, capacity);
    return written > 0 ? written - 1 : -1;
#elif defined(__APPLE__)
    uint32_t size = (uint32_t)capacity;
    if (_NSGetExecutablePath(buffer, &size) != 0) return -1;
    return (int)strlen(buffer);
#else
    ssize_t count = readlink("/proc/self/exe", buffer, (size_t)capacity - 1);
    if (count < 0) return -1;
    buffer[count] = '\0';
    return (int)count;
#endif
}

/* -------------------------------------------------------------------- images */

/* Decodes PNG/JPEG/BMP/TGA/GIF/HDR... into tightly packed RGBA8. Release with katsa_free. */
KATSA_EXPORT uint8_t* katsa_image_decode(const uint8_t* data, int size, int* width, int* height) {
    int components = 0;
    return stbi_load_from_memory(data, size, width, height, &components, 4);
}

KATSA_EXPORT const char* katsa_image_error(void) { return stbi_failure_reason(); }

/* Encodes RGBA8 as PNG into malloc memory. Returns NULL on failure. */
KATSA_EXPORT uint8_t* katsa_image_encode_png(const uint8_t* rgba, int width, int height, int* size) {
    return stbi_write_png_to_mem(rgba, width * 4, width, height, 4, size);
}

/* ------------------------------------------------------------------- vorbis */

/* Decodes an Ogg Vorbis file into interleaved 16-bit samples. Release with katsa_free. */
KATSA_EXPORT int16_t* katsa_vorbis_decode(const uint8_t* data, int size, int* channels, int* rate, int* frames) {
    int16_t* output = NULL;
    int count = stb_vorbis_decode_memory(data, size, channels, rate, &output);
    if (count < 0) return NULL;
    *frames = count;
    return output;
}
