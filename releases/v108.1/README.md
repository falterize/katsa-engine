# Katsa v108.1

Stage 2 of the migration plan, first increment. Open `Katsa-v108.1.love` with LÖVE 11.5 as before.

## What is new

* **katsa layer foundation** (`source/katsa`): LÖVE-dialect to GLSL 330 core / GLSL ES 300 shader translator, headless
  EGL platform (desktop GL 3.3 core and GLES 3.0), GL compile/link validation. Window, input, audio and 2D drawing on
  GL follow in later versions. See `docs/guides/katsa/platform.md`.
* **Audio modules**: `SoundManager` (`scene.audio.manager`), `AudioListener`, `AudioSource`.
  See `docs/guides/audio/audioModules.md`.
* **Constraint modules**: one module per constraint family under `nodes/physics/3d/constraintTypes/`; new
  `SliderConstraint3D` (`PrismaticConstraint3D` stays as an identical class).
* **Shader scopes**: `Shader2D` processes interface pixels only unless `affects3D = true`; `Shader3D` is limited to
  World3D hierarchies. Stare Shooter's retro filter and the platformer speed blur set `affects3D = true`.
* **No empty folders required**: scene category folders are no longer validated, so a repository clone or GitHub ZIP runs.

## Behaviour change

Shader2D no longer processes the 3D render behind it by default. Scenes that relied on that must set `affects3D = true`.
