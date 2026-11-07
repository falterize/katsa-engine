-- katsa.window.create(width, height, flags): an additional OS window sharing the main window's
-- OpenGL context. Draw into it with `window:draw(function() ... end)`.
local SubWindow = {}
SubWindow.__index = SubWindow

function SubWindow.new(platform, record, title)
    return setmetatable({ _platform = platform, _record = record, _title = title }, SubWindow)
end

local function bound(self, call)
    assert(self._record.raw, 'The window is closed')
    local platform = self._platform
    local main = platform.mainWindow or platform.window
    platform:bind(self._record.raw)
    local a, b = call(platform)
    platform:bind(main)
    return a, b
end

-- Renders `fn` into this window and presents it; clear it yourself with graphics.clear().
function SubWindow:draw(fn)
    assert(self._record.raw, 'The window is closed')
    katsa.graphics.drawToWindow(self._record, fn)
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
    bound(self, function(platform)
        platform:setPosition(x, y)
    end)
end

function SubWindow:getPosition()
    return bound(self, function(platform)
        return platform:getPosition()
    end)
end

function SubWindow:setSize(width, height)
    assert(self._record.raw, 'The window is closed')
    self._platform.sdl.SDL_SetWindowSize(self._record.raw, width, height)
end

function SubWindow:getSize()
    return bound(self, function(platform)
        return platform:getRawMode()
    end)
end

function SubWindow:setTitle(title)
    assert(self._record.raw, 'The window is closed')
    self._platform.sdl.SDL_SetWindowTitle(self._record.raw, title)
end

-- Opacity of the whole window, 0..1.
function SubWindow:setOpacity(opacity)
    bound(self, function(platform)
        platform:setOpacity(opacity)
    end)
end

function SubWindow:getOpacity()
    return bound(self, function(platform)
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

-- `listener(name, ...)` receives 'close', 'mousemoved' (x, y, dx, dy), 'mousepressed' /
-- 'mousereleased' (x, y, button) and 'wheelmoved' (x, y) of this window.
function SubWindow:setListener(listener)
    self._record.listener = listener
end

return SubWindow
