# v108.1 validation

* Full historical suite: **1345 checks passed, 0 failed** (`love . --test`, [log](logs/v108.1-full.log)).
* New focused suite: **36 checks passed** (`love . --test-v108.1`, [log](logs/v108.1-focused.log), JIT off:
  [log](logs/v108.1-focused-interpreter.log)): 30 audio-module checks (instrumented audio, no audible output) and 6 Shader2D/Shader3D scope checks including a rendered
  affects3D comparison (flat 3D colour 0.20/0.40/0.60 stays unchanged by default and becomes 0.80/0.60/0.40 with `affects3D`).
* Constraint families on both physics backends, now including SliderConstraint3D: 165 checks ([log](logs/v108.1-v103.log)).
* v107.2 authoring 300 checks ([log](logs/v108.1-authoring.log)); Physics2D 178 checks ([log](logs/v108.1-physics2d.log)).
* katsa layer, standalone LuaJIT: **109 checks** ([log](logs/v108.1-katsa.log)). Every project shader and 51 engine-generated
  shader variants compile and link on desktop GL 3.3 core and GLES 3.0 (Mesa llvmpipe).
* StyLua 2.6 check passed.

Not covered: real GPU output, window/DPI behaviour, audible audio and Windows; run on the target machine.

Archive: `Katsa-v108.1.love`  
Bytes: `20976912`  
SHA-256: `a525cf1c9592e5802f2a8625ec7f086810e0f724ac216a66c62cbb9f7acfe756`
