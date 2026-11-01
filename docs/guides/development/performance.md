# Runtime performance

## Explicit project frame pacing

Standalone projects can set a fallback `frameRateLimit` in their project module.
A scene can override it in `settings.lua`, including explicit zero. The engine
keeps foreground rendering uncapped unless a scene/project requests a ceiling.
A positive value requests
a frame ceiling, independent of Stats visibility. The loop waits until an actual
clock deadline after presentation, subtracting frame work already performed.
Supported Windows versions use a reusable high-resolution waitable timer; the
portable fallback blocks for at least 1 ms and rechecks the deadline. Neither
path busy-spins. Oversleep can reduce FPS but an early wake cannot bypass the
remaining wait. A frame already over budget receives no extra delay.

The previous one-shot fractional `katsa.timer.sleep` could return immediately for
waits below 1 ms. Measured requests of 0.25 and 0.75 ms took less than 0.001 ms;
this produced uneven pacing and FPS above the configured limit. That bug is
separate from the reported desktop stutter with Stats hidden. High FPS alone
has not been established as the cause of that stutter.

Pacing does not skip simulation updates, lower resolution, change physics
frequency or enable VSync. Sleep time is visible in the loop diagnostics.
Stats text refreshes four times per second; frame samples retain real deltas.

## JIT working set

`source/engine/core/runtime.lua` initializes the LuaJIT cache policy before scene
services load. It allows up to 8,000 traces and 32,768 KiB of machine code. The
latter is a machine-code ceiling, not total Lua/JIT memory or an immediate 32 MiB
allocation. Trace metadata and ordinary Lua data have separate memory costs.

The node/UI/physics workload can overflow smaller caches repeatedly, discarding
useful compiled paths and recompiling them during gameplay. A larger bounded
working set avoids that churn in the measured extended Rig + Physics workload.
The prior 8,192 KiB ceiling still filled during a longer rig run and forced a
global flush followed by recompilation. The current 32,768 KiB ceiling leaves
room for that working set; memory is allocated as needed, not all at startup. Initialization
does not change optimization flags, arithmetic accuracy, simulation frequency,
solver settings or native callback guards, and never enables a disabled JIT.
Unavailable JIT controls retain the platform's normal behavior; `Runtime.configured`
and `Runtime.error` expose setup status. Initialization is idempotent.

See the official [LuaJIT runtime parameter documentation](https://luajit.org/running.html)
for `maxtrace` and `maxmcode`. Cache tuning is process-wide and is separate from
the Jolt worker pool. Cold shader/asset/font creation and OS/driver waits can still
cause long initial frames; the cache policy is not a fixed minimum-FPS guarantee.

Stats labels with explicitly fixed geometry opt into paint-only text invalidation.
Their revision still changes for cached render targets, but text content alone
does not repeat geometry arrangement. Ordinary/custom UI retains normal text
layout invalidation. Only visible Stats rows need formatted display strings;
all available metric histories continue sampling. Scaled/rich text reuses native
Text drawables and updates their fonts/content without changing layout rules,
glyph density, wrapping, effects or colors. Unused runs are released on shrink,
mode change and node destruction.

## Reproducing stutter

Run `katsa . --profile-v106.1-stutter`. The runner loads Animation + Physics at
1920x1080, performs 120 frames with Stats closed, 60 with the list open and the
remaining frames with the FPS chart open. Default total: 900 frames. Updates are
fixed 1/60 for comparison; this is not an interactive gameplay FPS measurement.

`KATSA_STUTTER_LOG` selects an absolute per-frame CSV output path.
`KATSA_STUTTER_FRAMES` controls the frame count. `KATSA_STUTTER_JIT=1` enables a
test-only trace-event counter; normal gameplay never installs it. Reports separate
update, draw, present, physics and UI times, Lua memory deltas, native Text creation,
p95/p99/max and cache flush counts. Both cold and warm stages are retained.
`KATSA_STUTTER_TUNE=1` applies the same cache limits inside a historical runner copy
for experiments; the historical flag applies 8,192 KiB, while current startup
uses 32,768 KiB. No renderer readback or forced
full garbage collection occurs in the measurement loop.

Compare the same scene/window, visible Stats state, runtime and driver sequentially.
Do not compare a warmed hidden-Stats average with an open-chart minimum FPS.
Trace instrumentation has a cost; retain uninstrumented observations too. Detailed
release results and raw timelines belong in the external validation directory.


## UI allocation and clipping

Font-size probes measure line widths/heights without constructing temporary
lines, rich-text fragments or concatenated run strings. A fitting maximum size
ends the search immediately. A probe that already exceeds the available height
can stop early. The final drawable layout uses matching native-pixel glyph metrics while
retaining logical size limits, rich styles and target density. Plain text avoids unused stroke
callbacks and redundant origin transforms; fallback colors are read-only shared
values. Outlined text retains its exact-offset rendering path.

Stats rows clip their own content, allowing completely scrolled-out rows to be
rejected before background, font, modifier and GPU work. Metric histories keep
sampling independently. ScrollFrame drawing separates the outer frame clip from
the inset child window: children remain clipped, while bars use the frame's full
rectangle within ancestor clips and rounded stencil masks.

`katsa . --profile-v106.2-stutter` accepts the same profiler controls plus
`KATSA_STUTTER_SCENE=platformer` or `animationPhysicsLab`. The v106.2 runner
uses the current startup policy; `KATSA_STUTTER_MCODE_KIB=8192` explicitly
reproduces the old machine-code ceiling for diagnosis. Run at least 6,000
frames to include longer allocation/collection cycles. Optional
`KATSA_STUTTER_WIDTH` and `KATSA_STUTTER_HEIGHT` set the test window dimensions. The profiler reports
presentation separately: a large present time must not be attributed solely to
Lua, physics or UI. Desktop composition, other workloads and GPU queue waits can
vary between runs. Compare CPU phases and allocation tests as well as totals.


## Real frame loop

Foreground rendering has no artificial frame sleep or frame cap. VSync remains
configurable through LÖVE; unfocused/inactive windows retain a 10 ms idle wait.
The loop preserves standard event/quit handling, real timer deltas and full draw/
present execution. It does not busy-wait on a target deadline or change simulation
steps. Material uniform buffers and shader feature lists are reused; resource
normalization and image lookups avoid repeated hot-path temporary tables.

`katsa . --profile-v106.4-loop` runs the actual frame loop rather than manually
calling a fixed-delta benchmark. Set `KATSA_LOOP_LOG` to an absolute CSV path and
optionally `KATSA_LOOP_FRAMES` (default 2400). Stats opens automatically and the
first 240 frames are excluded. The log separates event pumping, present, sleep,
update, UI and physics. `KATSA_LOOP_PROFILE=1` enables optional LuaJIT sampling;
leave it off for performance comparisons.

Stats exposes previous-frame loop events/update/draw/present/sleep measurements.
An event-pump stall is not a solver or GC measurement. Event processing may include
window/driver/OS work; a large value narrows the investigation without proving
one specific cause. FPS retains the complete wall delta through these stalls.

## Static Menu presentation

The example Menu opts into reusing an unchanged window presentation. The loop
continues to process events and update UI, but skips GPU clear/draw/present until
the UI revision changes. Idle polling yields at up to 120 polls per second;
this is not a gameplay FPS cap. Animated UI, scene transitions, resize and focus
damage resume drawing immediately. Other scenes do not opt into this policy.


## Scene replacement and compiled references

LuaJIT traces can retain constants from scene-owned closures even when the root
trace belongs to a shared engine function. Clearing scene modules or their own
traces alone does not retire those references. SceneManager clears compiled code
after a successful replacement of a nonempty scene stack, or disposal through
`pop`. This is a scene-lifetime boundary, not a periodic frame/physics/GC action.
The next scene warms its traces again; asset/shader caches and solver settings
are unchanged. Failed preparation preserves the running scene and its code.

The real-time soak tests weak references to retired scenes as well as resource
counts and post-finalizer Lua retention. It does not flush code itself. See
[validation](validation.md) and the official [LuaJIT cache API](https://luajit.org/ext_jit.html).
