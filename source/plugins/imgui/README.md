# imgui plugin

Dear ImGui (cimgui, docking, 1.93) for katsa, bound with the LuaJIT FFI. Everything lives in this
folder; see `docs/guides/development/imgui.md` for usage, the build scripts in `build/` and the
template for binding other native libraries.

- `vendor/cimgui`: sources (pins in `UPSTREAM.md`), `native/`: compiled libraries (Linux x64 is
  committed; build the others with `build/buildNative.py`).
- Without a binary for the platform the engine falls back to its legacy Stats panel.
