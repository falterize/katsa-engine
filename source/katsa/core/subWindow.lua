-- katsa.window.create(width, height, flags): an additional OS window sharing the main window's
-- OpenGL context. Draw into it with `window:draw(function() ... end)`.
local SubWindow = {}
SubWindow.__index = SubWindow

function SubWindow.new(platform, record, title)
    return setmetatable({ _platform = platform, _record = record, _title = title }, SubWindow)
end

-- Runs `call(platform)` with the platform's window calls pointed at this window. No GL context
-- switch is involved, so state queries and moves are cheap.
local function aimed(self, call)
    assert(self._record.raw, 'The window is closed')
    local platform = self._platform
    local previous = platform.window
    platform:target(self._record.raw)
    local ok, a, b = pcall(call, platform)
    platform:target(previous)
    if not ok then
        error(a, 0)
    end
    return a, b
end

-- Renders `fn` into this window and presents it; clear it yourself with graphics.clear().
function SubWindow:draw(fn)
    assert(self._record.raw, 'The window is closed')
    katsa.graphics.drawToWindow(self._record, fn)
end

-- Runs `call(platform)` with window calls aimed at this window (advanced; no GL switch).
function SubWindow:call(fn)
    return aimed(self, fn)
end

function SubWindow:isOpen()
    return self._record.raw ~= nil
end

-- True once the user asked to close it (the window stays open until close() is called).
function SubWindow:isCloseRequested()
    return self._record.closeRequested == true
end

function SubWindow:close()
    self._platform:destroyWindow(self._record)
end

function SubWindow:setPosition(x, y)
    aimed(self, function(platform)
        platform:setPosition(x, y)
    end)
end

function SubWindow:getPosition()
    return aimed(self, function(platform)
        return platform:getPosition()
    end)
end

function SubWindow:setSize(width, height)
    assert(self._record.raw, 'The window is closed')
    self._platform.sdl.SDL_SetWindowSize(self._record.raw, width, height)
end

function SubWindow:getSize()
    return aimed(self, function(platform)
        return platform:getRawMode()
    end)
end

function SubWindow:setTitle(title)
    assert(self._record.raw, 'The window is closed')
    self._platform.sdl.SDL_SetWindowTitle(self._record.raw, title)
end

-- Opacity of the whole window, 0..1.
function SubWindow:setOpacity(opacity)
    aimed(self, function(platform)
        platform:setOpacity(opacity)
    end)
end

function SubWindow:getOpacity()
    return aimed(self, function(platform)
        return platform:getOpacity()
    end)
end

function SubWindow:setVisible(visible)
    assert(self._record.raw, 'The window is closed')
    local sdl = self._platform.sdl
    if visible then
        sdl.SDL_ShowWindow(self._record.raw)
    else
        sdl.SDL_HideWindow(self._record.raw)
    end
end

-- Window state, with the names of katsa.window (sizes and positions are raw pixels) -----------

function SubWindow:getMinimumSize()
    return aimed(self, function(platform)
        return platform:getMinimumSize()
    end)
end

function SubWindow:setMinimumSize(width, height)
    assert(self._record.raw, 'The window is closed')
    self._platform.sdl.SDL_SetWindowMinimumSize(self._record.raw, width, height)
end

-- The title bar and frame; true gives a borderless window.
function SubWindow:setBorderless(borderless)
    aimed(self, function(platform)
        platform:setBordered(not borderless)
    end)
end

function SubWindow:isBorderless()
    return aimed(self, function(platform)
        return not platform:isBordered()
    end)
end

function SubWindow:setResizable(resizable)
    aimed(self, function(platform)
        platform:setResizable(resizable)
    end)
end

function SubWindow:isResizable()
    return aimed(self, function(platform)
        return platform:isResizable()
    end)
end

-- mode: false, true / 'desktop' (borderless at desktop size) or 'exclusive'.
function SubWindow:setFullscreen(mode)
    return aimed(self, function(platform)
        return platform:setFullscreen(mode)
    end)
end

function SubWindow:isFullscreen()
    return aimed(self, function(platform)
        return platform:isFullscreen()
    end)
end

function SubWindow:getFullscreen()
    return aimed(self, function(platform)
        return platform:getFullscreen()
    end)
end

function SubWindow:toggleFullscreen()
    self:setFullscreen(not self:isFullscreen())
    return self:isFullscreen()
end

-- A topmost window stays above every other one; an owned window (the default) only stays above
-- the main window.
function SubWindow:setAlwaysOnTop(onTop)
    return aimed(self, function(platform)
        return platform:setAlwaysOnTop(onTop)
    end)
end

function SubWindow:center()
    aimed(self, function(platform)
        platform:center()
    end)
end

function SubWindow:getTitle()
    return self._title or ''
end

function SubWindow:minimize()
    assert(self._record.raw, 'The window is closed')
    self._platform.sdl.SDL_MinimizeWindow(self._record.raw)
end

function SubWindow:maximize()
    assert(self._record.raw, 'The window is closed')
    self._platform.sdl.SDL_MaximizeWindow(self._record.raw)
end

function SubWindow:restore()
    assert(self._record.raw, 'The window is closed')
    self._platform.sdl.SDL_RestoreWindow(self._record.raw)
end

-- Brings the window to the front and gives it the keyboard focus.
function SubWindow:focus()
    assert(self._record.raw, 'The window is closed')
    local sdl = self._platform.sdl
    sdl.SDL_RaiseWindow(self._record.raw)
    sdl.SDL_SetWindowInputFocus(self._record.raw)
end

function SubWindow:isFocused()
    return self._record.focused == true
end

-- Index (0 based) of the display the window is on; see katsa.window.getDisplayBounds.
function SubWindow:getDisplay()
    return aimed(self, function(platform)
        return platform:getDisplayIndex()
    end)
end

-- `listener(name, ...)` receives 'close', 'focus' (focused), 'mousemoved' (x, y, dx, dy),
-- 'mousepressed' / 'mousereleased' (x, y, button), 'wheelmoved' (x, y), 'keypressed' (key,
-- scancode, isRepeat), 'keyreleased' (key, scancode) and 'textinput' (text) of this window.
function SubWindow:setListener(listener)
    self._record.listener = listener
end

return SubWindow
