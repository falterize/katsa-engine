# v108.2 results

- `luajit source/tests/katsa/run.lua`: 113 passed, 0 failed (includes 60-scene archive in `.katsa` and fused form).
- Standalone host on Linux/Xvfb: fused 200-scene game (`g2exe`) and `katsa game.katsa` both pass scene transitions.
- `love . --test-v108.1`: 36 checks pass (no regression).
- Not verified here: Windows host build and run, macOS, Android, real GPU/audio (user hardware).
