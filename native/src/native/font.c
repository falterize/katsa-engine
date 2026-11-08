/*
 * katsa_native / font: TrueType rasterisation for katsa.graphics fonts (stb_truetype).
 *
 * Only TrueType outlines are supported (.ttf and TrueType-flavoured .otf); CFF outlines and
 * font collections beyond the first face are not.
 *
 * Units: stb_truetype metrics are in font units. Multiply them by the scale returned from
 * katsa_font_scale to get pixels.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "common/export.h"

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

/* stb_truetype keeps pointers into the font file, so the font owns a private copy of the bytes:
 * the Lua string or buffer the caller passed may be collected right after katsa_font_load. */
typedef struct KatsaFont {
    stbtt_fontinfo info;
    uint8_t* data;
} KatsaFont;

static const stbtt_fontinfo* info_of(void* handle) {
    return &((KatsaFont*)handle)->info;
}

/* Loads the first face of a font file. Returns a handle for the other functions (release with
 * katsa_font_free) or NULL when the data is not a supported font. */
KATSA_EXPORT void* katsa_font_load(const uint8_t* data, int size) {
    KatsaFont* font = (KatsaFont*)calloc(1, sizeof(KatsaFont));
    if (!font) {
        return NULL;
    }
    font->data = (uint8_t*)malloc((size_t)size);
    if (!font->data) {
        free(font);
        return NULL;
    }
    memcpy(font->data, data, (size_t)size);
    int offset = stbtt_GetFontOffsetForIndex(font->data, 0);
    if (offset < 0 || !stbtt_InitFont(&font->info, font->data, offset)) {
        free(font->data);
        free(font);
        return NULL;
    }
    return font;
}

KATSA_EXPORT void katsa_font_free(void* handle) {
    KatsaFont* font = (KatsaFont*)handle;
    if (font) {
        free(font->data);
        free(font);
    }
}

/* Scale factor (pixels per font unit) for a font size given as the em square in pixels. */
KATSA_EXPORT float katsa_font_scale(void* handle, float em_pixels) {
    return stbtt_ScaleForMappingEmToPixels(info_of(handle), em_pixels);
}

/* Vertical metrics in font units: ascent above the baseline (positive), descent below it
 * (negative) and the extra gap between lines. */
KATSA_EXPORT void katsa_font_vmetrics(void* handle, int* ascent, int* descent, int* line_gap) {
    stbtt_GetFontVMetrics(info_of(handle), ascent, descent, line_gap);
}

/* Glyph index of a Unicode code point; 0 means the font has no glyph for it. */
KATSA_EXPORT int katsa_font_glyph_index(void* handle, int codepoint) {
    return stbtt_FindGlyphIndex(info_of(handle), codepoint);
}

/* Horizontal metrics in font units: the advance to the next pen position and the left side
 * bearing. */
KATSA_EXPORT void katsa_font_hmetrics(void* handle, int codepoint, int* advance, int* lsb) {
    stbtt_GetCodepointHMetrics(info_of(handle), codepoint, advance, lsb);
}

/* Kerning between two code points in font units (usually negative or 0). */
KATSA_EXPORT int katsa_font_kern(void* handle, int cp1, int cp2) {
    return stbtt_GetCodepointKernAdvance(info_of(handle), cp1, cp2);
}

/*
 * Renders one glyph as an 8-bit coverage bitmap (one byte per pixel, rows top to bottom).
 * Sets its size and the offset of its top-left corner from the pen position in pixels (y down).
 * Returns the bitmap (release with katsa_free) or NULL for glyphs without pixels, e.g. a space.
 */
KATSA_EXPORT uint8_t* katsa_font_bitmap(void* handle, int codepoint, float scale, int* w, int* h,
                                        int* xoff, int* yoff) {
    return stbtt_GetCodepointBitmap(info_of(handle), scale, scale, codepoint, w, h, xoff, yoff);
}
