# v108.3

The engine runs on the katsa runtime instead of LÖVE.

- Graphics (OpenGL 3.3 / GLES 3.0 through SDL2), audio (OpenAL, silent fallback), physics (Box2D 2.3.1 in
  `katsa_box2d`), image, sound, filesystem, data and the archive readers are implemented in `source/katsa`,
  split by category (one concern per file).
- Archives: ZIP/`.katsa`, TAR, TAR.GZ and 7z (stored, LZMA, LZMA2; pure Lua decoder).
- `tools/build/packageProject.py` produces a `.katsa` archive or, with `--host`, a fused executable.
- Docs, tools and fixtures no longer reference LÖVE; `love.*` became `katsa.*`.
- Engine fixes found during the port: runtime objects are opaque values (not copied as tables),
  `graphics.push('all')` keeps the current font, shader uniforms accept plain numbers and flush queued draws,
  `SoundData:getSampleCount` counts frames, physics stays out of the JIT while native code can call back.
