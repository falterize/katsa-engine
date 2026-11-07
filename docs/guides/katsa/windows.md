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
| `setFullscreen(false / true / 'exclusive')`, `isFullscreen()`, `toggleFullscreen()` | Fullscreen |
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

Pass `alwaysontop = true` to keep a window above the main one (otherwise the main window can cover
it). Every window shares the main window's OpenGL context (so textures, canvases and shaders work
everywhere) and its pixel format. `window:draw(fn)` makes the window current, runs `fn`, presents
it and returns to the main window; graphics state (colour, transform, scissor) is saved and
restored, and an error inside `fn` is rethrown after the main window is restored. Call it from
`update` or `draw` of the main scene, never while a Canvas is active. Secondary windows present
without waiting for vertical sync; the main loop paces the frame.

| Call | Meaning |
| --- | --- |
| `katsa.window.create(w, h, flags)` | flags: `title x y resizable borderless alwaysontop hidden opacity` |
| `window:draw(fn)` | Render into the window and present |
| `setPosition(x, y)`, `getPosition()` | Raw pixel position on the desktop |
| `setSize(w, h)`, `getSize()` | Raw pixel size |
| `setTitle`, `setOpacity`, `getOpacity`, `setVisible` | Window properties |
| `setListener(fn)` | `fn(name, ...)` gets `close`, `mousemoved`, `mousepressed`, `mousereleased`, `wheelmoved` of that window |
| `isCloseRequested()`, `close()`, `isOpen()` | Closing the button only requests; call `close()` |

Keyboard and text input still go to the focused window's events through the main handlers.
The example scene `windowsLab` flies three windows around the main one (`T` toggles main window
opacity, `Space` pauses).
