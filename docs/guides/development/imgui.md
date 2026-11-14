# ImGui plugin

`imgui` puts [Dear ImGui](https://github.com/ocornut/imgui) (docking branch, 1.93) into scenes. It
is a plugin that stays inside `source/plugins/imgui`: the sources, the binaries, the LuaJIT FFI
binding and the katsa backend live there, and the core never requires it. The engine's own tools
(Stats, Scene tools) are ImGui windows when the library loads; without it the old Stats panel
and Tools button remain.

## Using it

Hotkeys in every collection scene: **F3** Stats, **F9** Scene tools, **F10** a *Tools* menu bar.
Windows can be dragged, resized and scrolled. The mouse and touch are captured only over a window,
so the game keeps receiving everything else.

Your own windows are a node:

```lua
local layer = world:create('ImGuiLayer', { name = 'Gui', theme = 'Dark', scale = 1 })
layer:connect('gui', function(ig)
    if ig.begin('Spawner') then
        if ig.button('Spawn') then spawn() end
        ig.text('Bodies: ' .. count)
    end
    ig.finish()  -- always, even when the window is collapsed
end)
```

| Property | Meaning |
| --- | --- |
| `theme` | `Dark`, `Light` or `Classic` |
| `scale` | UI scale (0.5 .. 3) |
| `showDemo` | ImGui's own demo window |

Scenes opt in with `plugins = { 'imgui' }`, or take the host that `Game` attaches itself.

<details><summary>Lua API (`ig`)</summary><br>

`ig` wraps the common calls and falls back to the raw C function for everything else:
`ig.Name(...)` calls `C.igName(...)`.

| Group | Functions |
| --- | --- |
| Windows | `begin(name, open, flags) -> visible, open`, `finish()`, `setNextWindowPos/Size/BgAlpha`, `beginChild/endChild` |
| Text | `text`, `textDisabled`, `textWrapped`, `textColored` |
| Layout | `separator`, `sameLine`, `spacing`, `indent`, `unindent`, `pushID`, `popID`, `setNextItemWidth` |
| Widgets | `button`, `checkbox -> changed, value`, `sliderFloat`, `sliderInt`, `dragFloat`, `combo(label, index, items)`, `colorEdit3`, `inputText(label, text) -> changed, text`, `selectable`, `progressBar`, `collapsingHeader`, `treeNode/treePop`, `plotLines` |
| Tables | `beginTable`, `endTable`, `tableSetupColumn`, `tableHeadersRow`, `tableNextRow`, `tableNextColumn` |
| Menus | `beginMainMenuBar/endMainMenuBar`, `beginMenu/endMenu`, `menuItem` |

`ig.C` is the raw cimgui table and `ig.ffi` the FFI module for the cases the wrapper does not cover.

</details>

<details><summary>Adding an engine tool window</summary><br>

A tool is a file in `source/plugins/imgui/tools/` listed in `tools/init.lua`:
`{ id, title, key?, new(), draw(ig, scene, state, host) }`. `new` returns the tool's private
state, `key` is the hotkey, `draw` runs every frame while the tool is open (`host:close(id)` closes
it). `stats.lua` and `sceneTools.lua` are the references. Tools read the scene through its public
methods (`toggleMusic`, `setTimeScale`, `resetView`, ...), so the legacy buttons and the windows
share one implementation.

</details>

<details><summary>How it is built (architecture)</summary><br>

| Folder | Role |
| --- | --- |
| `vendor/cimgui` | cimgui and Dear ImGui sources, unmodified (pins in `vendor/cimgui/UPSTREAM.md`) |
| `native/<os>-<arch>/` | the compiled library (`libcimgui.so`, `cimgui.dll`) |
| `binding/` | `cimgui.ffi.h` (generated cdef), `library.lua` (loads the binary), `api.lua` (the `ig` wrapper) |
| `backend/` | katsa glue: `input`, `keymap`, `textures`, `renderer`, `init` (context and frame) |
| `tools/`, `host.lua` | the engine's windows and the scene integration |
| `build/` | scripts that regenerate the cdef and build the binary |

Rendering uses `katsa.graphics` meshes, never raw GL, so the render-state cache stays truthful:
`ImDrawVert` (position, uv, rgba bytes) is exactly katsa's default vertex format, indices are 16-bit
and each draw command is a scissored `setDrawRange`. Fonts use ImGui's texture protocol
(`RendererHasTextures`); `backend/textures.lua` turns its requests into katsa images.

`Library.load()` returns `{ ffi, C, hash, platform }`, or `nil` and the reason when there is no
binary for the platform. The binary is copied to the save directory under a content hash before
loading (the same approach as the Jolt backend), and Android loads the library packaged in the APK.

</details>

<details><summary>Building the native library</summary><br>

Only a Linux x64 binary is committed. Build the others on their platform:

```sh
python3 source/plugins/imgui/build/buildNative.py                      # Linux, macOS (g++)
python3 source/plugins/imgui/build/buildNative.py                      # Windows: from an MSYS2 MinGW-w64 shell
ANDROID_NDK_HOME=/path/to/ndk python3 source/plugins/imgui/build/buildNative.py --android-abi arm64-v8a
python3 source/plugins/imgui/build/generateBindings.py                 # after updating vendor/cimgui
```

The result goes to `native/<os>-<arch>/`. Until a binary exists for a platform the scene runs
with the legacy Stats panel and Tools button, and `ImGui.reason()` says what is missing.

</details>

<details><summary>Binding another native library (template)</summary><br>

The plugin is the pattern for any C library:

1. Put its sources in `vendor/` and its binaries in `native/<os>-<arch>/`, inside one plugin folder.
2. Generate a cdef header with the preprocessor (`build/generateBindings.py`) and `ffi.cdef` it once.
3. Write `library.lua`: pick the binary for the platform, load it through
   `source.katsa.core.native`, return `nil, reason` instead of raising when it is missing.
4. Wrap the calls you use in a small Lua API and let the rest fall through to the raw functions.
5. Keep platform glue (input, drawing) in a backend that only talks to `katsa.*` APIs.
6. Make the feature optional: the engine must run, with a fallback, when the library does not load.

</details>

<details><summary>Troubleshooting</summary><br>

- **`Missing ImGui native library`**: no binary for this platform, build it (above).
- **Process aborts with `imgui.cpp: Assertion ...`**: ImGui asserts on API misuse (unbalanced
  `begin`/`finish`, sized table columns without a sizing policy). The message names the window.
- **Windows cover the on-screen joystick**: windows start in the upper half; drag them away.
- **No Stats window**: F3 toggles it; check `scene.imguiReason` when the library failed to load.

</details>
