# Device benchmark

`tools/diagnostics/androidBench` is a standalone game (own `main.lua`, no scenes) that times the
pieces a phone is suspected to be slow at and prints the table on screen and in the log:

| Row | What it tells |
| --- | --- |
| Lua math cold / warm, Lua strings | CPU speed and JIT warm-up (cold vs warm) |
| shader compile, 4 programs | driver shader compiler cost (total and worst) |
| window size x20000 / x2000 | cost of the SDL call that the platform caches per frame |
| idle, 200 rects, 20 overdraws, 2000 rects, 120 text lines | fps and CPU draw ms with one load at a time: fill rate (overdraws) vs draw submission vs text |
| drag test | touch moves delivered per frame while a finger drags (after the table is complete) |

A tap on the finished screen runs it again (second run shows the warm numbers).

## Building

Run the **native** workflow from the Actions page with *bench* ticked (arm64 only) and install `katsa-bench-apk`. It
has the same package name as the game APK, so it replaces it; reinstall the game APK afterwards.
Locally: `python3 android/prepare.py --abis arm64-v8a --project tools/diagnostics/androidBench`
then the Gradle build, as in [building](../katsa/building.md). On a PC the game runs from an
archive: `python3 tools/build/packageKatsa.py --source . --project tools/diagnostics/androidBench
--with-runtime --output bench.katsa` and `luajit tools/dev/katsa.lua bench.katsa` (software GL, so
only the CPU rows mean anything there).
