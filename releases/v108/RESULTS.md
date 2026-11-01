# v108 validation

- Full historical suite: **1345 checks passed, 0 failed**. Command: `love . --test`. [Log](logs/v108-test.log). The v107.2 baseline passed 1343 and failed one order-dependent check ([baseline log](logs/baseline-v107.2-full.log)); the cause was a test that never consumed its expected missing-manifest report, fixed in the test.
- New focused suite: **35 checks passed**. Command: `love . --test-v108`. [Log](logs/v108-test-v108.log), [interpreter log](logs/v108-test-v108-interpreter.log) (`KATSA_TEST_INTERPRETER=1`, JIT disabled). Covers slow-motion smoothing in both 3D solvers, Camera2D following the interpolated pose at 144 Hz and in slow motion, fov/focalLength linkage, projection against the GPU view-projection matrix in both modes, orthographic rays, culling, picking and a rendered orthographic frame, orthographic-only zoom/orthoSize/orthoNear, near-plane clipping behind the camera and wall-clock Animator pose rate under TimeScale.
- Regression suites: v107.2 authoring 300 checks ([log](logs/v108-test-v107.2-authoring.log)), Physics2D 178 checks ([log](logs/v108-test-physics2d.log)).
- Red-first reproduction: before the fixes the new tests failed with 12/119 changing frames (yaw) and a 1.60-unit camera-to-sprite pose error; after the fixes 110/119 and 1e-14.
- Rendered orthographic and perspective frames of the Models scene were inspected visually.
- StyLua 2.6 check passed for first-party source (`--syntax LuaJIT`), and the v107.2 baseline was verified clean with the same version.
- Python packaging and tool tests pass (`testPackaging.py` 7 tests, `testTools.py` 8 tests). [Source/archive audit](audit.json): 33 scene folders with 10 categories each; 1063 English text files; 1567 runtime and 56 private imports resolved. 227 assets/vendor/fixtures preserved against v107.2.
- Exact ZIP inventory: 1179 files and 680 directories, no marker files. Archive contents match canonical source.

Environment: Ubuntu container, LOVE 11.5 AppImage, Xvfb with Mesa llvmpipe (software OpenGL). Not covered: real GPU output, window/DPI behavior, audio devices and Windows; run `Start-*.bat` on the target machine to check those.

Archive: `Katsa-v108.love`  
Bytes: `20951295`  
SHA-256: `399cdd4ddbb07c9a34757400c35885cbfc217d814b11c0306ffe387ce6e6ca5b`
