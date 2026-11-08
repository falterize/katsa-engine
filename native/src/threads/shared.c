/*
 * katsa_threads / shared: reference-counted memory blocks and atomics for SharedArray.
 *
 * A block is plain memory any thread may read and write through FFI pointers. The library only
 * manages its lifetime (a reference count per holder) and offers int32 atomics; coordinating
 * access is up to the Lua code (source/katsa/thread/sharedArray.lua).
 */
#include <stdlib.h>

#include "threads.h"

/* The header in front of the payload. 16 bytes, so the payload keeps malloc's 16-byte alignment
 * on 64-bit systems (SharedArray stores doubles and int64 values there). */
typedef struct KShared {
    int32_t refs;
    int32_t padding;
    uint64_t size; /* payload bytes */
} KShared;

/* Payload slack: keeps a handful of bytes readable past `size` so vectorized readers that round
 * up to 16 bytes stay inside the allocation. */
#define PAYLOAD_SLACK 16

static KShared* header(void* handle) {
    return (KShared*)handle;
}

/* A zero-filled block of `size` bytes with one reference. Returns its handle, or NULL. */
KATSA_EXPORT void* kt_shared_new(size_t size) {
    KShared* block = (KShared*)calloc(1, sizeof(KShared) + size + PAYLOAD_SLACK);
    if (!block) {
        return NULL;
    }
    block->refs = 1;
    block->size = size;
    return block;
}

KATSA_EXPORT void* kt_shared_data(void* handle) {
    return (unsigned char*)handle + sizeof(KShared);
}

KATSA_EXPORT size_t kt_shared_size(void* handle) {
    return (size_t)header(handle)->size;
}

/* Adds a reference (another state or thread holds the block now). */
KATSA_EXPORT void kt_shared_retain(void* handle) {
    __atomic_add_fetch(&header(handle)->refs, 1, __ATOMIC_SEQ_CST);
}

/* Drops a reference and frees the block when none is left. Returns the references left. */
KATSA_EXPORT int kt_shared_release(void* handle) {
    int left = __atomic_sub_fetch(&header(handle)->refs, 1, __ATOMIC_SEQ_CST);
    if (left == 0) {
        free(handle);
    }
    return left;
}

KATSA_EXPORT int kt_shared_refs(void* handle) {
    return __atomic_load_n(&header(handle)->refs, __ATOMIC_SEQ_CST);
}

/* ---------------------------------------------------------------------------------------------- */
/* Atomics on int32 slots of shared memory. All are sequentially consistent: simplest to reason */
/* about, and the cost is irrelevant at the rate Lua calls them.                                 */
/* ---------------------------------------------------------------------------------------------- */

KATSA_EXPORT int32_t kt_atomic_load(int32_t* slot) {
    return __atomic_load_n(slot, __ATOMIC_SEQ_CST);
}

KATSA_EXPORT void kt_atomic_store(int32_t* slot, int32_t value) {
    __atomic_store_n(slot, value, __ATOMIC_SEQ_CST);
}

/* Adds `value` and returns the new contents. */
KATSA_EXPORT int32_t kt_atomic_add(int32_t* slot, int32_t value) {
    return __atomic_add_fetch(slot, value, __ATOMIC_SEQ_CST);
}

/* Stores `desired` if the slot holds `expected`. Returns 1 when it did. */
KATSA_EXPORT int kt_atomic_cas(int32_t* slot, int32_t expected, int32_t desired) {
    return __atomic_compare_exchange_n(slot, &expected, desired, 0, __ATOMIC_SEQ_CST,
                                       __ATOMIC_SEQ_CST);
}
