/*
 * katsa_native: the small C layer under the katsa runtime.
 *
 * It exists only where LuaJIT's FFI cannot be portable: UTF-8 file access on Windows and
 * directory listing (filesystem.c), and decoders for images, Ogg Vorbis and TrueType fonts
 * (image.c, audio.c, font.c, all built on the stb single-file libraries in vendor/stb).
 * Everything else in katsa is Lua over SDL2, OpenGL and OpenAL.
 *
 * Lua declarations: source/katsa/core/nativeLib.lua. Build: tools/native/build.py.
 */
#include <stdlib.h>

#include "common/export.h"

/* Bumped when an exported function is added, so Lua can tell an older library apart. */
KATSA_EXPORT int katsa_version(void) {
    return 1;
}

/* Releases every buffer this library hands to Lua (file data, pixels, samples, glyph bitmaps). */
KATSA_EXPORT void katsa_free(void* pointer) {
    free(pointer);
}
