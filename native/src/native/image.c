/*
 * katsa_native / image: decoding and PNG encoding for katsa.image and screenshots (stb_image).
 *
 * stb_image decodes PNG, JPEG, BMP, TGA, GIF (first frame), PSD, HDR and PIC. Results are always
 * converted to tightly packed RGBA8, rows top to bottom.
 */
#include <stdint.h>

#include "common/export.h"

/* No stdio: data always comes from memory (the archive or katsa_fs_read). STBI_FAILURE_USERMSG
 * makes stbi_failure_reason() readable for error messages. */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#define STBI_FAILURE_USERMSG
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO
#include "stb_image_write.h"

enum { RGBA = 4 };

/* Decodes an encoded image to RGBA8. Returns pixels (release with katsa_free) or NULL; on NULL
 * katsa_image_error() says why. */
KATSA_EXPORT uint8_t* katsa_image_decode(const uint8_t* data, int size, int* width, int* height) {
    int source_components = 0; /* what the file had; the output is RGBA either way */
    return stbi_load_from_memory(data, size, width, height, &source_components, RGBA);
}

/* The reason of the last failed decode on this thread. The string is static; do not free it. */
KATSA_EXPORT const char* katsa_image_error(void) {
    return stbi_failure_reason();
}

/* Encodes RGBA8 pixels as PNG. Returns the file bytes (release with katsa_free) and sets *size,
 * or NULL. */
KATSA_EXPORT uint8_t* katsa_image_encode_png(const uint8_t* rgba, int width, int height,
                                             int* size) {
    int stride = width * RGBA;
    return stbi_write_png_to_mem(rgba, stride, width, height, RGBA, size);
}
