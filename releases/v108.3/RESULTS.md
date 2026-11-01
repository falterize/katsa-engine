# v108.3 results

Linux, LuaJIT 2.1, Xvfb with Mesa llvmpipe, no sound card (OpenAL Soft null backend).

- `luajit source/tests/katsa/run.lua`: 207 passed, 0 failed (includes 7z stored/LZMA/LZMA2, OpenAL driver, texture statistics).
- `katsa . --test`: 1348 passed, 0 failed.
- `--test-v108`: 36, `--test-v108.1`: 37, `--test-v107.2-authoring`: 301, `--test-v107.1`: 1348, `--test-foundation`: 95, `--test-v83`: 55 passed.
- Packaged `Katsa-v108.3.katsa` runs `--test-v108.1` (37 passed).
- Sweep of the 83 `--test*` flags: all current flags pass except the items below.

Known gaps
- `--test-v96` and later flags that chain it: "Incremental dynamic frame matches forced preparation" differs in 0.26% of
  pixels (renderer cache versus forced preparation); v81 "Dense opaque lit scene uses early depth". Needs a check on a real GPU.
- Flags for versions v47–v78 and `--test-shadows` target features removed from the engine (for example `environment.sun`) and fail on those.
- `--test-data-session` needs its write/read phase argument; `--test-structure` expects the LÖVE project layout.
- mp3/flac decoding, OpenAL effects (EFX), line anti-aliasing and hinted-font fidelity are not implemented.
- Not verified here: Windows host build, macOS, Android, real GPU and audio hardware.
