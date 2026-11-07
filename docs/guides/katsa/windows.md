# Windows: transparency and extra OS windows

## Transparent main window

The framebuffer always has destination alpha (set `transparent = false` in the first window flags
to drop it). Turn transparency on at any time and clear the frame with alpha 0:

```lua
katsa.window.setTransparent(true)               -- Windows: DWM blends with the desktop
katsa.window.setBorderless(true)                -- overlay look, no title bar
katsa.window.setAlwaysOnTop(true)
katsa.window.setOpacity(0.8)                    -- the whole window, 0..1, independent of the above
-- in a scene: scene.clearColor = { 0, 0, 0, 0 } on a camera-free scene, or
-- katsa.graphics.setBackgroundColor(0, 0, 0, 0) in a plain katsa program
```

`setTransparent` is the GLFW technique on Windows (`DwmEnableBlurBehindWindow` with an empty blur
region); macOS and Linux compositors use the framebuffer alpha without help. It needs a compositor
and cannot be verified in the development sandbox: confirm on the target system. If nothing shows,
`setOpacity` (the whole window) always works.

## Size, borders, fullscreen (Godot's DisplayServer names)

| Call | Meaning |
| --- | --- |
| `setSize(w, h)`, `getSize()` | Window size in **pixels** |
| `getMinimumSize()`, `setMode(w, h, { minwidth, minheight })` | Minimum size |
| `setBorderless(b)`, `isBorderless()` | Hide / show the title bar and frame |
| `setResizable(b)`, `isResizable()` | Resizing by the user |
| `setFullscreen(false / true / 'exclusive')`, `isFullscreen()`, `getFullscreen()` (false / 'desktop' / 'exclusive'), `toggleFullscreen()` | Fullscreen |
| `setAlwaysOnTop(b)`, `center()`, `setPosition(x, y)`, `getPosition()` | Placement |

**F11** (and Alt+Enter) toggles fullscreen in every scene; remove the check in
`source/engine/scenes/bootstrap.lua` (`katsa.keypressed`) to disable it, or call
`katsa.window.toggleFullscreen()` from your own key handler.

While the user holds the title bar or an edge, Windows and macOS stop the normal frame loop. The
engine now keeps updating and drawing from SDL's event watch during that time (at most one frame
per 8 ms, and only while the OS loop is running), so the game no longer freezes. Extra windows made
by `window:draw` are redrawn in those frames too.

## More windows

```lua
local window = katsa.window.create(260, 170, { title = 'Tool', x = 100, y = 100, alwaysontop = true })
window:setPosition(300, 200)
window:draw(function()
    katsa.graphics.clear(0.1, 0.1, 0.15, 1)
    katsa.graphics.print('Hello', 10, 10)
end)
if window:isCloseRequested() then window:close() end
```

By default a new window is **owned by the main window**: it stays above it and minimises with it,
but never fights the other windows for the top of the z-order (several `alwaysontop` windows that
overlap flicker over each other). Pass `alwaysontop = true` for a topmost window, or
`owner = false` for a completely independent one. Every window shares the main window's OpenGL
context (so textures, canvases and shaders work everywhere) and its pixel format. `window:draw(fn)`
makes the window current, runs `fn`, presents it and returns to the main window; graphics state is
saved and restored, and an error inside `fn` is rethrown after the main window is restored. Call it
from `update` or `draw` of the main scene, never while a Canvas is active. Secondary windows present
without waiting for vertical sync; the main loop paces the frame.

**Cost.** Moving, resizing and presenting an OS window is a few milliseconds on Windows. Refresh
several windows in turns (one per frame, round robin, as `windowsLab` does), skip `setPosition`
when the position did not change, and prefer `runScene` below, which already limits itself to
`fps` frames per second.

| Call | Meaning |
| --- | --- |
| `katsa.window.create(w, h, flags)` | flags: `title x y resizable borderless alwaysontop owner hidden opacity fullscreen minwidth minheight` |
| `window:draw(fn)` | Render into the window and present |
| `setPosition(x, y)`, `getPosition()`, `center()` | Raw pixel position on the desktop |
| `setSize(w, h)`, `getSize()`, `setMinimumSize`, `getMinimumSize` | Raw pixel size |
| `setBorderless(b)`, `isBorderless()` | Title bar and frame |
| `setResizable(b)`, `isResizable()` | User resizing |
| `setFullscreen(false/true/'exclusive')`, `isFullscreen()`, `getFullscreen()`, `toggleFullscreen()` | Per-window fullscreen |
| `setAlwaysOnTop(b)`, `minimize()`, `maximize()`, `restore()`, `focus()`, `isFocused()`, `getDisplay()` | Window state |
| `setTitle`, `setOpacity`, `getOpacity`, `setVisible` | Window properties |
| `setListener(fn)` | `fn(name, ...)` gets `close`, `focus`, `mousemoved`, `mousepressed`, `mousereleased`, `wheelmoved`, `keypressed`, `keyreleased`, `textinput` of that window |
| `isCloseRequested()`, `close()`, `isOpen()` | Closing the button only requests; call `close()` |
| `window:runScene(source, options)` | A whole scene in the window (below) |

Desktop geometry for placing windows anywhere on the screen: `katsa.window.getDesktopSize()`,
`getDisplayCount()` and `getDisplayBounds(index)` (x, y, width, height). Windows may be resized
and moved at any time; a program that imitates a pop-up or a "virus" window that follows the
player, jumps around the desktop or grows can simply call `setPosition` / `setSize` every frame
(see the cost note above).

## A scene in its own window

```lua
local window = katsa.window.create(640, 400, { title = 'Mini game', resizable = true })
local second = window:runScene('platformer', { fps = 60 })
-- second:getScene(), second:isOpen(), second:close()
```

`runScene` gives the window its own scene manager, world, renderer, UI and input, so a full second
scene (any scene id, folder or package that works as the main scene) runs beside the main one:
every node type works, the window's mouse, wheel and keyboard events reach that scene, it is
re-fitted when the window is resized, and closing the window (or `second:close()`) releases the
scene. Options: `fps` (refresh ceiling, default 60), `clearColor`, `onClose(scene)` (return `false`
to keep the window open when the user presses its close button). All scenes share the GL context,
so assets are loaded once per scene manager but textures and shaders are compatible. Closing the
main scene's window quits the application and closes every window scene.

The example scene `windowsLab` flies three windows around the main one (`T` toggles main window
opacity, `B` the title bar, `R` resizes the windows, `M` opens a mini game in a window, `Space`
pauses).
