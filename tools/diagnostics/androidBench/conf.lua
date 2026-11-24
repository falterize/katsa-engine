-- Device benchmark: a standalone game (conf.lua + main.lua, no scenes) that times the pieces a
-- phone is suspected to be slow at and shows the table on screen. Build the APK with
-- `python3 android/prepare.py --project tools/diagnostics/androidBench` (or the native workflow
-- with project = bench); see docs/guides/development/deviceBench.md.
return {
    title = 'Katsa Bench',
    identity = 'katsa-bench',
    console = true,
}
