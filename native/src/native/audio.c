/*
 * katsa_native / audio: Ogg Vorbis decoding for katsa.audio (stb_vorbis).
 *
 * stb_vorbis.c is a whole implementation in one file and defines short macros (L, C, R ...);
 * it is compiled only in this translation unit so they cannot leak into other files.
 */
#include <stdint.h>

#include "common/export.h"

#define STB_VORBIS_NO_STDIO
#include "stb_vorbis.c"

/*
 * Decodes a whole Ogg Vorbis file into interleaved signed 16-bit samples.
 * Sets *channels, *rate (Hz) and *frames (samples per channel). Returns the samples
 * (release with katsa_free) or NULL when the data is not valid Vorbis.
 */
KATSA_EXPORT int16_t* katsa_vorbis_decode(const uint8_t* data, int size, int* channels, int* rate,
                                          int* frames) {
    int16_t* samples = NULL;
    int count = stb_vorbis_decode_memory(data, size, channels, rate, &samples);
    if (count < 0) {
        return NULL;
    }
    *frames = count;
    return samples;
}
