/*
 * KATSA_EXPORT marks the functions a Katsa library exposes to LuaJIT's FFI.
 *
 * Every library is compiled with -fvisibility=hidden, so only functions marked here appear in the
 * shared library's export table. The names and signatures are an ABI: the Lua side declares them
 * with ffi.cdef (source/katsa/.../binding.lua). Renaming or changing one breaks every game that
 * ships the older Lua runtime with the newer library, so treat them as frozen.
 */
#ifndef KATSA_COMMON_EXPORT_H
#define KATSA_COMMON_EXPORT_H

#if defined(_WIN32)
#define KATSA_EXPORT __declspec(dllexport)
#else
#define KATSA_EXPORT __attribute__((visibility("default")))
#endif

#endif
