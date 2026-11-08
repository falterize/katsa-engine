/*
 * The host's ZIP reader: finds STORE entries of the archive appended to the executable.
 *
 * Only what boot needs is implemented: the end-of-central-directory record, the central
 * directory and local headers of uncompressed entries. No ZIP64, no compression, no encryption;
 * the Lua runtime (source/katsa/core/archive.lua) reads everything else once it runs.
 *
 * Offsets inside the archive are relative to its first byte, but the archive starts after the
 * host executable. The start is recovered from the end record: the central directory ends right
 * before it, so  start = end_record - directory_size - directory_offset.
 *
 * Every read is bounds-checked: a truncated or corrupt archive yields "not found", never a read
 * outside the image.
 */
#include <stdint.h>
#include <string.h>

#include "host.h"

/* Record signatures and fixed sizes from the ZIP specification (APPNOTE.TXT, section 4.3). */
#define END_SIGNATURE 0x06054b50u
#define END_SIZE 22
#define MAX_COMMENT 65535
#define CENTRAL_SIGNATURE 0x02014b50u
#define CENTRAL_SIZE 46
#define LOCAL_SIGNATURE 0x04034b50u
#define LOCAL_SIZE 30
#define METHOD_STORE 0

/* ZIP integers are little endian. */
static uint32_t read16(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8);
}

static uint32_t read32(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/* True when [offset, offset + count) lies inside the image. */
static int inside(const HostImage* image, size_t offset, size_t count) {
    return offset <= image->size && count <= image->size - offset;
}

/* Offset of the end-of-central-directory record. It is the last 22 bytes of the file unless the
 * archive has a comment (up to 64 KB), so the search walks backwards over at most that much. */
static int find_end_record(const HostImage* image, size_t* offset) {
    if (image->size < END_SIZE) {
        return 0;
    }
    size_t last = image->size - END_SIZE;
    size_t limit = last > MAX_COMMENT ? last - MAX_COMMENT : 0;
    for (size_t at = last;; at--) {
        if (read32(image->data + at) == END_SIGNATURE) {
            *offset = at;
            return 1;
        }
        if (at == limit) {
            return 0;
        }
    }
}

const unsigned char* host_archive_find(const HostImage* image, const char* name, size_t* length) {
    size_t end;
    if (!find_end_record(image, &end)) {
        return NULL;
    }
    const unsigned char* record = image->data + end;
    uint32_t entries = read16(record + 10);
    uint32_t directory_size = read32(record + 12);
    uint32_t directory_offset = read32(record + 16);
    if ((size_t)directory_size + directory_offset > end) {
        return NULL;
    }
    size_t start = end - directory_size - directory_offset; /* the archive's first byte */
    size_t at = start + directory_offset;
    size_t name_length = strlen(name);

    for (uint32_t i = 0; i < entries; i++) {
        if (!inside(image, at, CENTRAL_SIZE)) {
            return NULL;
        }
        const unsigned char* entry = image->data + at;
        if (read32(entry) != CENTRAL_SIGNATURE) {
            return NULL;
        }
        uint32_t method = read16(entry + 10);
        uint32_t compressed_size = read32(entry + 20);
        uint32_t size = read32(entry + 24);
        uint32_t entry_name_length = read16(entry + 28);
        uint32_t extra_length = read16(entry + 30);
        uint32_t comment_length = read16(entry + 32);
        uint32_t local_offset = read32(entry + 42);
        if (!inside(image, at + CENTRAL_SIZE, entry_name_length)) {
            return NULL;
        }

        if (entry_name_length == name_length
            && memcmp(entry + CENTRAL_SIZE, name, name_length) == 0) {
            if (method != METHOD_STORE || compressed_size != size) {
                return NULL; /* compressed entries are for the Lua reader */
            }
            size_t local = start + local_offset;
            if (!inside(image, local, LOCAL_SIZE)
                || read32(image->data + local) != LOCAL_SIGNATURE) {
                return NULL;
            }
            /* The local header has its own name and extra field lengths, which may differ from
             * the central directory's. */
            size_t data = local + LOCAL_SIZE + read16(image->data + local + 26)
                          + read16(image->data + local + 28);
            if (!inside(image, data, size)) {
                return NULL;
            }
            *length = size;
            return image->data + data;
        }
        at += CENTRAL_SIZE + entry_name_length + extra_length + comment_length;
    }
    return NULL;
}
