/*
 * The Katsa host: a tiny executable that starts LuaJIT on the Lua runtime stored in a ZIP archive
 * appended to the executable itself. Becomes katsa.exe on Windows, katsa on Linux/macOS and
 * libmain.so on Android.
 *
 * Layout of a runnable file:
 *
 *     [host executable][ZIP archive]
 *
 * The archive holds the Lua runtime as STORE (uncompressed) entries under source/katsa/ plus
 * __katsa/boot.lua, and, for a fused game, the game files. The host only reads STORE entries;
 * everything else, including compressed entries, is done in Lua.
 *
 * Files:
 *   main.c        process entry, the Lua state and the `katsa_host` global
 *   image.c       finding and reading the executable (the "image") on desktop systems
 *   android.c     the Android variants: logcat output and the archive copied from the APK
 *   archive.c     the STORE-only ZIP reader
 */
#ifndef KATSA_HOST_H
#define KATSA_HOST_H

#include <stddef.h>

/* The executable as one buffer; the archive lies at its end. Filled by host_load_image. */
typedef struct HostImage {
    char path[4096];     /* UTF-8 path of the file that holds the archive */
    unsigned char* data; /* the whole file */
    size_t size;
} HostImage;

/* Writes an error line to stderr (logcat on Android). `detail` may be NULL. */
void host_report(const char* message, const char* detail);

/* Finds the file that holds the archive and reads it whole into `image`. Returns 1 on success.
 * argv0 is the fallback path on systems that cannot name the running executable. */
int host_load_image(HostImage* image, const char* argv0);

/* Releases the buffer of host_load_image. */
void host_free_image(HostImage* image);

/* Looks up a STORE entry of the ZIP archive at the end of `image`. Returns a pointer into the
 * image and sets *length, or returns NULL when the entry is missing, compressed or malformed. */
const unsigned char* host_archive_find(const HostImage* image, const char* name, size_t* length);

#if defined(__ANDROID__)
/* Sends stdout and stderr (Lua's print, io.stderr) to logcat. */
void host_android_redirect_output(void);

/* Reads image->path whole into the image (image.c); android.c fills the path first. */
int host_read_image_file(HostImage* image);
#endif

#endif
