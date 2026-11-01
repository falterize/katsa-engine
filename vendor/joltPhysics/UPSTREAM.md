# Jolt dependency provenance

- Physics engine: Jolt Physics v5.6.0, as selected by the pinned joltc CMake project.
- C API repository: https://github.com/amerkoleci/joltc
- C API commit: `2bbcf73b1bec261e0351814662922f1b4784454c`.
- Binary provider: https://github.com/amerkoleci/JoltPhysicsSharp
- Binary provider commit: `e468f1f30ef74726a799ceef1f8427fa39867e93`.
- Exact binary URLs, lengths and SHA256 digests: [provenance.json](provenance.json).

`include/joltc.h` is the pinned upstream header. `include/joltc.ffi.h` is its generated single-precision LuaJIT form; regenerate it with `tools/build/jolt/generateBindings.py` from the project root. This transformation removes C preprocessor/export syntax and adapts declarations for LuaJIT FFI without changing the selected ABI.

The supplied Windows x64, Linux x64 and Android ARM/ARM64 binaries are unmodified upstream artifacts. No .NET runtime or C# execution is used. Windows x64 is runtime-tested; the other included libraries are integrity-checked.

The full upstream C++ source trees are not bundled. To modify or rebuild the native library, obtain joltc at the commit above and follow its CMake dependency pin for Jolt v5.6.0. Build with the single-precision/shared-library settings documented in [README.md](README.md). Preserve the ABI, update provenance for any rebuilt artifact, then rerun native and integration checks.

Project-specific Lua loading, callbacks, body/constraint adapters and compatibility policy live under `source/engine/physics/3d/backends/jolt/`. They are separate from these third-party artifacts. Included MIT notices cover joltc, Jolt Physics and JoltPhysicsSharp.
