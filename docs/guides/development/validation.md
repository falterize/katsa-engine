# Repeatable validation

Run these commands from the repository root. Python 3.12+ and a built katsa runtime
are sufficient for the Python/Lua runners; native dependency verification uses only
bundled files and hashes, without network access. Everything lives in `validation/`:
tests in `validation/tests`, generated logs in `validation/logs` (not committed).

```text
python tools/testing/checkProject.py test --output validation/logs/runtime
python tools/testing/checkProject.py soak --output validation/logs/soak
python tools/testing/checkProject.py benchmark --output validation/logs/benchmark
```

`--katsa` accepts a katsa executable path. The default launcher uses `katsa` on PATH.
Use `--project path/to/release.katsa`
to validate a packaged release rather than the source directory. Each child has
a timeout; errors, nonzero exits or missing completion markers fail the command.
Logs stay in the chosen output directory. Scripts do not download dependencies.

## Functional regressions

`test` runs the complete suite with JIT, then in interpreter mode. It covers both
backends and previous scene/UI/skin/shadow regressions, plus rate aggregation,
bounded frame samples, save interruption/corruption/recovery, ordered migrations,
newer-version protection, preferences and standalone scene lifetime/assets.

Use `katsa . --test-v107.1-authoring` for spatial scale/shear, stable hierarchy order,
visual hierarchy/picking/opacity and per-world gravity on all three solvers.
Use `katsa . --test-physics2d` for 2D simulation, constraints, Camera2D and editable/image collider tests. `katsa . --test-foundation` retains the persistence/frame-pacing checks. Save tests create/remove
only dedicated `validation-v1068` slots. Tests require write access to the
application's save directory for temporary data and exported test logs.
Do not run multiple test processes against the same identity concurrently.

Static checks and dependency verification:

```text
python tools/testing/checkStyle.py
luajit validation/tests/katsa/run.lua
python tools/build/jolt/prepareNative.py
```

Game archives omit `validation/`. To run the suites from a package, build it with
`python tools/build/packageProject.py --with-validation` and start `katsa <archive> --test`.

Formatting uses the supplied `stylua.toml` with StyLua 2.6.0. No vendor files need
reformatting.

## Real-time Menu and scene soak

Default soak: 60 seconds of idle Menu, then 50 complete Menu -> Rig + Physics ->
Menu cycles, alternating Jolt/Oimo, with Stats/history open in the physics scene.
Each scene is held for half a second. Unlike a tight synthetic update loop, this
uses the real event/update/draw/present path and allows Menu window-frame reuse.
It asserts that the idle policy actually activates, previous resource scopes
release, Menu ownership/cache counts stop growing, the runtime journal stays
empty, retired scene weak references clear, and post-GC Lua retention stays within 8 MiB of the warmed baseline.

```text
python tools/testing/checkProject.py soak --idle 120 --cycles 100 --hold 1
```

Progress appears in the log at each cycle. A JSON report is written under
`validation-logs/` in the application's save directory. Two full collections allow finalizers and their dependent objects to clear. Collections are
diagnostic checkpoints between cycles, not a new gameplay GC policy. A stable
resource count and bounded Lua retention do not prove the absence of every native
driver leak. Hardware focus, DPI, mobile touch and long play sessions still need
device testing. The existing functional suite exercises resize/scroll routing;
the soak focuses on idle behavior and repeated teardown.

## Matched physics benchmark

Default benchmark runs Rig + Physics at 1920 x 1080, VSync off, seed 1068, Stats
and the FPS plot open. It performs Jolt -> Oimo -> Oimo -> Jolt in one process,
recreating the scene with the same random seeds for every phase. Each phase has
five seconds of warmup followed by 30 seconds of measurements. The reversed
second pair helps expose order/thermal effects; results are still hardware and
OS dependent. Quality, solver iterations, scene content and simulation code are
not reduced by the runner.

```text
python tools/testing/checkProject.py benchmark --warmup 5 --seconds 30 --width 1920 --height 1080
```

Keep the katsa window focused and do not interact with the scene. Samples observed
without window focus are rejected and counted. A run with rejected samples,
no frames, or an exhausted sample buffer has `valid = false`; do not use it for
a backend comparison. The runner does not fake focus or disable the normal
background policy. Prefer repeated valid runs on an otherwise idle system.

Reports are saved under `benchmark-logs/physics-<UTC>-<timer>/` in the application
save directory. Each phase has raw per-frame milliseconds in CSV; `summary.json`
records engine/runtime, renderer/device, actual window size, MSAA/VSync, seeds,
warmup/sample settings, backend, configured workers, rejected frames, physics
timings and frame statistics. Physics timings are CPU observations, not GPU time.

- FPS is frames / summed frame seconds.
- Mean frame time is summed frame milliseconds / frames.
- p95/p99 use nearest-rank frame-time percentiles (lower is better).
- Worst frame and frames exceeding the 60 Hz time budget expose isolated stalls.
- The 300,000-sample cap bounds memory per phase. Report calculation, sorting and
  disk writes happen between measured phases, not every frame.

These tools diagnose smoothness; they do not impose a 60 FPS cap or promise a
minimum frame rate on every device. The [Stats guide](statistics.md) explains
why schema-1 arithmetic FPS exports cannot be compared directly to corrected
FPS means.
