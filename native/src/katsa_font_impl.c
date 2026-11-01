/* Font rasterisation for katsa.graphics (stb_truetype). TrueType outlines only. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#if defined(_WIN32)
#define KATSA_EXPORT __declspec(dllexport)
#else
#define KATSA_EXPORT __attribute__((visibility("default")))
#endif

typedef struct { stbtt_fontinfo info; uint8_t* data; } KatsaFont;

KATSA_EXPORT void* katsa_font_load(const uint8_t* data, int size) {
    KatsaFont* font = (KatsaFont*)calloc(1, sizeof(KatsaFont));
    if (!font) return NULL;
    font->data = (uint8_t*)malloc((size_t)size);
    if (!font->data) { free(font); return NULL; }
    memcpy(font->data, data, (size_t)size);
    int offset = stbtt_GetFontOffsetForIndex(font->data, 0);
    if (offset < 0 || !stbtt_InitFont(&font->info, font->data, offset)) {
        free(font->data); free(font); return NULL;
    }
    return font;
}

KATSA_EXPORT void katsa_font_free(void* handle) {
    KatsaFont* font = (KatsaFont*)handle;
    if (font) { free(font->data); free(font); }
}

KATSA_EXPORT float katsa_font_scale(void* handle, float em_pixels) {
    return stbtt_ScaleForMappingEmToPixels(&((KatsaFont*)handle)->info, em_pixels);
}

KATSA_EXPORT void katsa_font_vmetrics(void* handle, int* ascent, int* descent, int* line_gap) {
    stbtt_GetFontVMetrics(&((KatsaFont*)handle)->info, ascent, descent, line_gap);
}

KATSA_EXPORT int katsa_font_glyph_index(void* handle, int codepoint) {
    return stbtt_FindGlyphIndex(&((KatsaFont*)handle)->info, codepoint);
}

KATSA_EXPORT void katsa_font_hmetrics(void* handle, int codepoint, int* advance, int* lsb) {
    stbtt_GetCodepointHMetrics(&((KatsaFont*)handle)->info, codepoint, advance, lsb);
}

KATSA_EXPORT int katsa_font_kern(void* handle, int cp1, int cp2) {
    return stbtt_GetCodepointKernAdvance(&((KatsaFont*)handle)->info, cp1, cp2);
}

/* 8-bit coverage bitmap; release with katsa_free. NULL for empty glyphs. */
KATSA_EXPORT uint8_t* katsa_font_bitmap(void* handle, int codepoint, float scale, int* w, int* h, int* xoff, int* yoff) {
    return stbtt_GetCodepointBitmap(&((KatsaFont*)handle)->info, scale, scale, codepoint, w, h, xoff, yoff);
}
