# Testing and build verification

From the source root:

```text
love . --test
love . --test-v106.7
love . --test-skin-menu
love . --test-menu-idle
love . --test-v106.6
love . --test-v106.5
love . --test-v106.4
love . --test-v105
love . --test-v106
love . --test-v106.1
love . --test-v106.2
love . --test-v106.3
love . --test-v105.2
love . --test-v105-parallel
love . --test-v104
love . --test-structure
love . --physics-oimo --test-v104-selection
love . --physics-oimo --test-v102
love . --physics-oimo --test-v75
love . --physics-jolt --stress-v103
python tools/build/jolt/prepareNative.py
python tools/build/jolt/generateBindings.py --check
python tools/build/packageProject.py --output dist
```

Historical command names identify stable suites, not the current application version. Set `KATSA_TEST_INTERPRETER=1` to exercise supported suites with JIT disabled. The v104 suite covers both physics backends, mutation safety, lifecycle and animation caches. v102 covers rendering/UI regressions; v75 compares retained text geometry. Stress scenes check bounded finite body poses and debug drawing.

Format first-party Lua using `stylua --syntax LuaJIT --verify source/engine source/game source/tests main.lua conf.lua`, followed by the same paths with `--check`. Preserve vendor files and historical comparison fixtures. Python tools use the checked-in Black configuration.

Release-wide runners, frame-hash comparisons, structural audits and completed results live in the external `validation/` directory beside the release archive. Re-test the packaged `.love` after changes to dependency paths. A Haxe/C++ rebuild requires the corresponding external compiler; library hash verification does not claim a source rebuild or device testing.

The v105 suite covers both scroll axes, automatic bounds, direction changes, inspector properties, invalid inputs, native worker execution and body-ID reuse. The forced-parallel suite runs the 174 existing adapter checks with the worker threshold set to zero, including contact mutation and scene teardown. `--benchmark-v105` measures CPU physics on a fixed scene; see [parallel physics](../physics/parallel.md).

Run `--test-v105.1-quality` for native Windows DPI, font density, image sampling
and MSAA checks. `--test-v105.1-regression` runs the historical 196-check suite
with its explicit non-MSAA depth-prepass fixture. The rig profiler accepts
`KATSA_PROFILE_MSAA=0` or `2` to separate CPU changes from AA cost.

`--test-v105.2` covers logical UI sizes and input at 100%, 125%, 150% and 200%,
logical-coordinate high-DPI targets, reference fitting, lazy Jolt snapshots,
immediate setters, moving-body triggers, replacement collider queries and debug
drawing. Run with `KATSA_TEST_INTERPRETER=1` for the interpreter path.

`--test-v106` covers bounded history, spike preservation, means, gaps, invalid
samples, scene/world backend selection, actual backend labels, every metric plot,
click/drag routing and custom canvas snapshot tracking. It runs both solvers; set
`KATSA_TEST_INTERPRETER=1` to check the interpreter path. Set `KATSA_PREVIEW_PATH`
to an absolute PNG path for an inspected Stats preview from the same suite.

`--test-v106.1` checks CSV scopes/windows, escaping, unavailable data, collision-safe
saving, dialog choices, fixed-text paint invalidation, retained glyph buffers and
the runtime cache policy. JIT OFF remains supported. Optional
`KATSA_REFERENCE_TEXT` points to a trusted older `text.lua` for pixel comparisons;
`KATSA_EXPORT_FIXTURE` writes a CSV fixture for an independent parser round-trip.
See [runtime performance](performance.md) for the open-Stats stutter profiler.


`--test-v106.2` checks save migration, collision handling, failed reads/writes,
identity restoration, current save location, paused diagnostic readers and frame
gap timing. Pixel checks cover X/Y/XY bars, both vertical positions, every inset
mode, overflowing parents, and 100%/125%/200% UI scales. Optional trusted
`KATSA_REFERENCE_TEXT` enables comparisons with an older text implementation:
plain/RichText, empty lines, Unicode symbols, narrow wrapping, chosen font sizes
and exact pixel bytes at three densities. A GC-stopped fixture measures temporary
text-layout allocation; forced collection is confined to this test fixture.


`--test-v106.3` compares plain/scaled/RichText pixel bytes against independent
physical-font draws at 75%, 100%, 125%, 150%, 175% and 200%. It checks CanvasGroup
alpha compositing/cache reuse, both scrollbar directions/positions, content
panning, track/end clamping, invisible bars, canceled clicks, Slider ownership,
world-panel coordinate conversion, ViewportFrame overlays and VirtualJoystick.
Both JIT modes are supported. `KATSA_TEXT_PREVIEW` selects an optional absolute
PNG output path for the 125% text fixture.

The historical `KATSA_REFERENCE_TEXT` switches compare older rendering policies;
exact agreement at fractional scales is intentionally no longer the quality
criterion. Use the v106.3 native-pixel reference suite for the current path.
Run `--preview-v106.3` with `KATSA_UI_PREVIEW_PREFIX` set to an absolute filename
prefix to capture real menu and Workspace screenshots.


`--test` now selects the current `--test-v106.4` suite. It covers scene folders,
ZIP/.love/TAR/TAR.GZ/TGZ/7z packages, archive ownership, resource URI aliases,
GLTF/OBJ sidecars, audio, custom nodes, explicit systems and all gameplay scenes
on both backends. `KATSA_TEST_INTERPRETER=1` checks its interpreter path.
The original integration runner predates current shader includes and menu order;
current regression coverage uses versioned suites instead of that stale runner.
Use `--test-v102` for the retained 196 rendering/UI/Oimo checks and
`--test-v106.3` for the current typography/scrolling pixel policy.

`--test-v106.5` runs the retained package/backends coverage plus all
29 scene folder contracts, lifecycle-only exports, menu/catalog/pause startup,
private node ownership and folder/ZIP/.love/TAR/TAR.GZ/TGZ/7z lifecycle fixtures.
It checks discovery, deterministic order, initially disabled startup, runtime
enabling, all three update phases, exactly one simulation/UI update, private
module caches and cleanup. The frame-loop probe also has the alias
`--profile-v106.5-loop`; use `KATSA_LOOP_LOG` for the output CSV.

`--test` / `--test-v106.6` adds categorized script/UI entry checks and marker-free
scene directories to the retained lifecycle suite. It exercises TAR directory
conversion, including a conventional `.` root directory, as well as all existing
scene/archive formats. External `validation/testPackaging.py` checks project and
scene archive entries, empty categories, cache/output exclusion, rebuilding into
the project root and preservation of an existing release on invalid input.

The updated v106.6 suite also checks scene layout version 3 with scripts/ui,
compatibility with version 2 root-ui archives, and the documented Spinner node:
inherited mounting/defaults, automatic processing, adopt identity/idempotence,
hierarchy snapshots, signals and owned cleanup. See nodeAuthoring.md for the API.

`--test-stare-shooter` runs the Godot port's controller checks on both backends:
all six FSM states, speeds, acceleration, crouch dimensions/foot position, jump and
landing, Q/backward clip direction, mouse/zoom bounds, input routing, system
disabling, imported clip durations, eight-weight skin attributes and cleanup.
The current `--test` suite includes these checks. Set `KATSA_TEST_OUTPUT` to an
existing absolute directory to save first/third-person, retro and wireframe PNGs.
Set `KATSA_STARE_SCENE` to an exported scene ZIP to run the same checks from that
archive instead of the installed folder.


`--test-skin-menu` checks per-instance skin reduction, normalized strongest
weights, palette splitting, triangle preservation, restoring defaults, resource
release, wireframe, shadow coherence, configurable menu keys and touch routing
on both Jolt and Oimo. `--test-v106.7` includes this and the full scene suite.
Set `KATSA_TEST_OUTPUT` to an existing absolute directory for PNG previews.

`--test-menu-idle` checks retained Menu presentation, bounded idle resources,
text/category/scroll/resize invalidation, animated UI, focus damage and return
to uncapped gameplay. The main-loop fixture verifies that idle Menu polling
does not clear, redraw or present the same frame repeatedly.

## Current release validation

`--test` runs the current v106.8 suite, including previous regressions, corrected
FPS aggregation, persistence failure/recovery/migration cases and standalone
scene loading. `--test-v106.8` selects it explicitly; `--test-foundation` runs the
new cases alone. For JIT/interpreter runs, a real-time Menu/scene soak and
a matched backend benchmark, see [repeatable validation](validation.md).

## Collider model sources

Run `love . --test-v107.2-authoring` for focused editor/physics authoring coverage,
including OBJ/GLB/glTF path loading on Oimo/Jolt, independent point extraction,
invalid-source recovery and the Collision Models Workspace path picker.
