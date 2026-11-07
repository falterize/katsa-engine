# Windows: transparency and extra OS windows

## Transparent main window

Pass `transparent = true` in the window flags (`conf.lua` or `katsa.window.setMode` at the first
call). The framebuffer then keeps destination alpha, so a frame cleared with alpha 0
(`katsa.graphics.clear(0, 0, 0, 0)`) shows the desktop behind it where the OS compositor allows.
Combine with `borderless = true` for an overlay-style window and `alwaysontop = true` to keep it on
top.

```lua
katsa.window.setMode(800, 600, { borderless = true, transparent = true, alwaysontop = true })
katsa.window.setOpacity(0.8)   -- the whole window, 0..1
```

Limits: per-pixel transparency is up to the compositor. It works on macOS and on Linux with a
compositing window manager. On Windows an OpenGL window shows the alpha channel only through DWM
tricks that are not implemented, so there `setOpacity` (whole window) is the reliable tool. Verify on
your target system; the development sandbox has no compositor.

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

Every window shares the main window's OpenGL context (so textures, canvases and shaders work
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
