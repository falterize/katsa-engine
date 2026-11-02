# Statistics and history

Open Stats with its toolbar button or F3. The header reports the scene, actual
physics backend, requested backend, fallback status, runtime/JIT and light loop.
Scenes without a physics world report `none`. Explicit backend requests fail if
unavailable; only `auto` may fall back.

Click any numeric row to open its history. The popup provides:

- Current value, retained 30-second mean and recent 5-second mean.
- A plot window of 5 or 30 seconds, with minimum and maximum values.
- Green bars for each bucket's mean, whiskers for its minimum/maximum, and a
  yellow line for the selected window's mean. Newest samples are on the right.

Drag the list or use the wheel to scroll. Dragging a row does not activate it.
Close the plot with X; close Stats with F3 or its toolbar button. Textual metadata
such as the backend name does not have a numeric plot.

History uses the manager's diagnostic frame clock and 120 reusable quarter-second
buckets per metric. Lightweight FPS, frame duration, focus, Stats visibility,
configured ceiling and CPU/loop timings continue while Stats is hidden. This
allows exporting the preceding stall after opening Stats, without collecting
physics/graphics counters or creating the numeric UI rows while hidden. Detailed
metrics record only while visible and preserve gaps when unavailable.

Rows and detailed histories are created on first use. Opening Stats preserves the
existing background history. New buckets reuse bounded storage after the ring
fills. Numeric labels and graphics-counter queries refresh at 4 Hz; frame histories
still retain every sampled frame and its bucket min/max. Frame durations use the
same loop boundary each time, so variable event-pump offsets do not invent FPS
spikes. The primary row is instantaneous; use the 5/30-second mean for throughput.

Non-rate means weight recorded samples, not the number of buckets. FPS means
use completed frames divided by their summed unclamped frame durations, both
inside bars and across the selected window. Current/min/max FPS remain
instantaneous reciprocals of frame delta. Window boundaries include whole
quarter-second buckets. This fixes the upward bias of arithmetic instantaneous
FPS averages; values from older exports use the older definition. Renderer timings are CPU observations, not GPU timestamps.
`Manager:update(simulationDelta, realDelta)` accepts an optional full frame delta;
main.lua supplies it before clamping simulation to 100 ms. A long stall therefore
remains visible in Stats without changing the existing simulation/UI timestep.
Callers supplying only one delta retain the original API and use it for diagnostics.
Draw-call counts are queried at display refresh after 3D submission and before
Stats/UI submission. Between queries the last graphics snapshot is retained.
Unavailable metrics display `--`; the popup reports `unavailable` for the current
value instead of adding fabricated zeroes. A scene without native physics has no
native-solver samples. Shadow A/B values appear only after an explicit probe.

## Library layout

```text
source/engine/debug/statistics/
  history.lua    generic bounded ring, rate/arithmetic means, ranges and monotonic-time validation
  chart.lua      StatisticsChart UI node and bar/range rendering
  panel.lua      reusable clickable metric list, plot selection and presentation
  export.lua     manual CSV snapshots and collision-safe save filenames
  definitions.lua shared metric readers and descriptive labels
  frameTimes.lua bounded exact frame samples for offline percentile reports
source/game/ui/statistics.lua
                 compatibility entry point for the shared definitions
```

Game rendering delegates to the scene adapter instead of assembling a large Stats
string. To add a metric, add a stable id, label, optional unit and `read(context)`
function to the panel definitions. A reader returns a finite number or nil when
unavailable. Sampling is opt-in through `panel:sample(context, time, visible)`;
call `panel:resize()` after fitting the owning UI. Each panel owns its definitions
and histories. No third-party dependency is required.

For isolated use, `History.new(capacity, interval, optionalAggregation)`, `history:sample(time, value)`,
`history:get(index)` and `history:summary(seconds, reusableOutput, optionalTime)` are independent
of katsa rendering. `get(1)` is the oldest retained bucket. Do not mutate internal
buckets; `summary` can reuse a caller-owned result table to avoid allocations. An explicit current
time lets unavailable metrics age out even when their last sample is older.

Recording and displaying Stats has a measurement cost. For release comparisons,
measure both closed Stats and the inspection workload rather than assuming the
overlay is free. See [testing](testing.md) and [parallel physics](../physics/parallel.md).

## Export logs

Choose **Export Stats logs...** in the Stats list, or **Export logs...** in a
metric popup. Select one of four explicit options: selected value / last 5s,
selected value / last 30s, all Stats / last 5s, or all Stats / last 30s. Value-only
options require a selected metric; all-Stats export also works from the list.
The export dialog captures pointer input until closed. Stats keeps recording
while the dialog is open.

**Export without the panel:** press **F6** (or *Export Stats CSV* in the F4 menu, or call
`scene.statistics:export(30)`) to save the last 30 seconds. Frame, loop and update histories are
recorded in the background, so the panel can stay hidden; panel-only metrics are marked unavailable.
The saved path is written to the console.

CSV files are saved in `stats-logs/` inside `katsa.filesystem.getSaveDirectory()`.
Use **Open log folder** to locate them. No network request or automatic disk
logging occurs. Filenames include UTC time, scope/metric and window length;
numeric suffixes prevent overwriting existing files. The save identity is
`katsa-engine`; see [save data](saveData.md) for the one-time legacy migration.

The CSV contains schema/application version, export UTC, scene, actual backend,
scope, window length/end time, metric id/label/unit, bucket start, last sample
time, sample count, mean, minimum, maximum and last value. Schema 2 appends
`aggregation` and `duration_seconds`: FPS uses `events/seconds`, other metrics
use `arithmetic`. The FPS mean is `samples / duration_seconds` for a bucket. Values
use a locale-independent decimal point and 17-digit precision; labels are quoted
and escaped when necessary. Files use UTF-8 and CRLF record separators.

Logs export the retained quarter-second buckets shown by Stats, rather than
inventing individual frame samples after aggregation. Selection uses each bucket's
last sample time; a boundary bucket may include samples up to a quarter-second
before the requested window. Zero-count rows with blank numeric fields identify
unavailable metrics. Closing Stats stops recording; export does not backfill gaps.
Serialization and writing occur only after a manual export action.

The scene adds CPU update time and previous-frame screen UI time to help compare
spikes with physics/render observations. The previous-frame label is intentional:
Stats samples before drawing its own UI. These are CPU times, not GPU timings.
For the startup cache policy and stutter profiler, see [runtime performance](performance.md).


`Window focused` distinguishes active gameplay from the focus-loss pause. While
unfocused, scene update and physics readers return unavailable data instead of
repeating the last active measurement. Rendering/UI metrics continue to describe
the frames actually drawn. Missing update samples leave a gap in that history.

`Between-frame wait / events` measures elapsed wall time from the previous
manager draw completion to the next manager update. It includes presentation,
event processing, the katsa loop sleep and OS scheduling; it is not a GPU timer
and cannot identify a driver problem by itself. It helps locate waits outside
the measured scene update and screen UI work. FPS still uses the full real frame
delta, including long frames; it is never clamped or smoothed to hide spikes.


`Loop events/update/draw/present/sleep (previous frame)` split the real outer loop.
These values are committed only when a whole loop iteration finishes, so Stats
never mixes a partially recorded current draw with a previous presentation.
Present is CPU wall time spent in the call, not an asynchronous GPU duration.
The new metrics use the same chart history and selected/all 5s/30s exports.

## Interpreting FPS averages

The FPS metric samples `1 / frameDelta`. Its mean is the arithmetic average of
instantaneous FPS samples, so uneven frame times can make it higher than the
actual number of frames divided by elapsed time. Compare the **Frame delta**
mean and its spikes as well. For the same samples, `1000 / meanFrameMilliseconds`
gives the effective frame rate. This distinction matters when comparing a
60 Hz fixed-step solver across uncapped render frames.


For matched backend runs, exact frame-time CSVs and p95/p99 reports, see
[repeatable validation](validation.md). The full guide explains focus rejection
and why average FPS alone cannot establish smoothness.

2D worlds add Box2D to the backend header and CSV metadata. Numeric physics2D.*
metrics include total/solver milliseconds, fixed steps, body/fixture/contact/joint
counts, sleeping bodies and dropped simulation time. These use the same plots,
retention and selected/all 5/30-second exports as existing 3D metrics.

World2D and World3D time-scale rows expose each scene world independently of the existing application-wide scale row.
