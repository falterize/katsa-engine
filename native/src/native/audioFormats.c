/*
 * katsa_native / audio formats: MP3 and FLAC decoding for katsa.audio (dr_mp3, dr_flac).
 *
 * Each dr_* header is a whole implementation; they are compiled only in this translation unit,
 * apart from stb_vorbis (audio.c), so their macros cannot leak into other files.
 */
#include <stdint.h>

#include "common/export.h"

#define DR_MP3_IMPLEMENTATION
#define DR_MP3_NO_STDIO
#include "dr_mp3.h"

#define DR_FLAC_IMPLEMENTATION
#define DR_FLAC_NO_STDIO
#include "dr_flac.h"

/*
 * Both decoders read a whole file into interleaved signed 16-bit samples. They set *channels,
 * *rate (Hz) and *frames (samples per channel) and return the samples (release with
 * katsa_free), or NULL when the data is not valid.
 */
KATSA_EXPORT int16_t* katsa_mp3_decode(const uint8_t* data, int size, int* channels, int* rate,
                                       int* frames) {
    drmp3_config config;
    drmp3_uint64 count = 0;
    drmp3_int16* samples =
        drmp3_open_memory_and_read_pcm_frames_s16(data, (size_t)size, &config, &count, NULL);
    if (!samples) {
        return NULL;
    }
    *channels = (int)config.channels;
    *rate = (int)config.sampleRate;
    *frames = (int)count;
    return samples;
}

KATSA_EXPORT int16_t* katsa_flac_decode(const uint8_t* data, int size, int* channels, int* rate,
                                        int* frames) {
    unsigned int flacChannels = 0, flacRate = 0;
    drflac_uint64 count = 0;
    drflac_int16* samples = drflac_open_memory_and_read_pcm_frames_s16(
        data, (size_t)size, &flacChannels, &flacRate, &count, NULL);
    if (!samples) {
        return NULL;
    }
    *channels = (int)flacChannels;
    *rate = (int)flacRate;
    *frames = (int)count;
    return samples;
}
