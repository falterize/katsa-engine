-- Extra OS windows for the SDL2 platform. All windows share the main window's OpenGL context and
-- pixel format; drawing into one makes it current, renders and swaps, then returns to the main
-- window (see graphics.drawToWindow). Positions and sizes are in raw pixels.
local ffi = require('ffi')

return function(Platform, K)
    -- Window opacity (0..1, the whole window) of the main window.
    function Platform:setOpacity(opacity)
        return self.sdl.SDL_SetWindowOpacity(self.window, math.max(0, math.min(1, opacity))) == 0
    end

    function Platform:getOpacity()
        local value = ffi.new('float[1]', 1)
        self.sdl.SDL_GetWindowOpacity(self.window, value)
        return value[0]
    end

    function Platform:setPosition(x, y)
        self.sdl.SDL_SetWindowPosition(self.window, x, y)
    end

    function Platform:getPosition()
        local x, y = ffi.new('int[1]'), ffi.new('int[1]')
        self.sdl.SDL_GetWindowPosition(self.window, x, y)
        return x[0], y[0]
    end

    -- Window state of the main window, in raw pixels, with the names of Godot's DisplayServer.
    function Platform:setSize(width, height)
        self.sdl.SDL_SetWindowSize(self.window, width, height)
    end

    function Platform:getMinimumSize()
        local w, h = ffi.new('int[1]'), ffi.new('int[1]')
        self.sdl.SDL_GetWindowMinimumSize(self.window, w, h)
        return w[0], h[0]
    end

    local function hasFlag(self, flag)
        return require('bit').band(self.sdl.SDL_GetWindowFlags(self.window), flag) ~= 0
    end

    function Platform:isBordered()
        return not hasFlag(self, K.BORDERLESS)
    end

    function Platform:setBordered(bordered)
        self.sdl.SDL_SetWindowBordered(self.window, bordered and 1 or 0)
    end

    function Platform:isResizable()
        return hasFlag(self, K.RESIZABLE)
    end

    function Platform:setResizable(resizable)
        self.sdl.SDL_SetWindowResizable(self.window, resizable and 1 or 0)
    end

    function Platform:isFullscreen()
        return hasFlag(self, K.FULLSCREEN)
    end

    -- false, 'desktop' or 'exclusive'. SDL's desktop flag includes the exclusive bit.
    function Platform:getFullscreen()
        local flags = require('bit').band(self.sdl.SDL_GetWindowFlags(self.window), K.FULLSCREEN_DESKTOP)
        if flags == K.FULLSCREEN_DESKTOP then
            return 'desktop'
        end
        return flags ~= 0 and 'exclusive' or false
    end

    -- mode: false (windowed), true or 'desktop' (borderless at desktop size), 'exclusive'.
    function Platform:setFullscreen(mode)
        local flag = 0
        if mode == 'exclusive' then
            flag = K.FULLSCREEN
        elseif mode then
            flag = K.FULLSCREEN_DESKTOP
        end
        return self.sdl.SDL_SetWindowFullscreen(self.window, flag) == 0
    end

    -- SDL_SetWindowAlwaysOnTop needs SDL 2.0.16; older libraries keep the creation-time flag only.
    function Platform:setAlwaysOnTop(onTop)
        local ok = pcall(function()
            self.sdl.SDL_SetWindowAlwaysOnTop(self.window, onTop and 1 or 0)
        end)
        return ok
    end

    function Platform:center()
        self.sdl.SDL_SetWindowPosition(self.window, K.CENTERED, K.CENTERED)
    end

    -- Native handle of a window on Windows (nil elsewhere or when SDL cannot provide it).
    local function nativeHandle(self, raw)
        local info = ffi.new('SDL_SysWMinfo')
        self.sdl.SDL_GetVersion(ffi.cast('uint8_t*', info.version))
        if self.sdl.SDL_GetWindowWMInfo(raw, info) == 0 then
            return nil
        end
        return info.info.win.window
    end

    -- Makes `owner` the owner of `raw`: it stays above it, minimises with it and never fights the
    -- other windows for the top of the z-order (unlike always-on-top, which lets every such window
    -- flicker over the next one). Windows uses an owned window; X11 and Wayland a transient one.
    function Platform:setOwner(raw, owner)
        if ffi.os == 'Windows' then
            return (pcall(function()
                ffi.cdef('intptr_t SetWindowLongPtrW(void* window, int index, intptr_t value);')
                local user = ffi.load('user32')
                local parent = nativeHandle(self, owner)
                assert(parent, 'no native handle')
                user.SetWindowLongPtrW(nativeHandle(self, raw), -8, ffi.cast('intptr_t', parent))
            end))
        end
        return (pcall(function()
            return self.sdl.SDL_SetWindowModalFor(raw, owner) == 0
        end))
    end

    -- Points the window calls (position, size, flags...) at `raw` without touching the GL context.
    -- Callers restore the previous window with the same call.
    function Platform:target(raw)
        self.mainWindow = self.mainWindow or self.window
        self.window = raw
    end

    -- Displays: bounds of display `index` (0 based) in raw pixels, the primary one by default.
    function Platform:getDisplayCount()
        return self.sdl.SDL_GetNumVideoDisplays()
    end

    function Platform:getDisplayBounds(index)
        local rect = ffi.new('SDL_Rect')
        if self.sdl.SDL_GetDisplayBounds(index or 0, rect) ~= 0 then
            return nil
        end
        return rect.x, rect.y, rect.w, rect.h
    end

    function Platform:getDisplayIndex()
        return self.sdl.SDL_GetWindowDisplayIndex(self.window)
    end

    -- ffi.cdef redefining a type raises, so the declarations are made once (setTransparent runs
    -- again when a scene leaves and restores the opaque window).
    local dwmDeclared
    local function declareDwm()
        if dwmDeclared then
            return
        end
        ffi.cdef([[
            typedef struct { uint32_t flags; int enable; void* region; int transition; } KatsaBlurBehind;
            int DwmEnableBlurBehindWindow(void* window, const KatsaBlurBehind* behind);
            void* CreateRectRgn(int left, int top, int right, int bottom);
            int DeleteObject(void* object);
        ]])
        dwmDeclared = true
    end

    -- Per-pixel transparency of the main window. Linux and macOS compositors honour the alpha
    -- channel of the framebuffer by themselves; on Windows the window must be told to blend with
    -- the desktop (DWM), the way GLFW does it. Returns whether the call could be made.
    function Platform:setTransparent(enabled)
        self.transparent = enabled
        if ffi.os ~= 'Windows' then
            return true
        end
        local ok, message = pcall(function()
            declareDwm()
            local handle = nativeHandle(self, self.window)
            if not handle then
                error('SDL_GetWindowWMInfo failed')
            end
            local dwm, gdi = ffi.load('dwmapi'), ffi.load('gdi32')
            -- An empty blur region switches per-pixel alpha on without blurring anything.
            local region = gdi.CreateRectRgn(0, 0, -1, -1)
            local behind = ffi.new('KatsaBlurBehind', 3, enabled and 1 or 0, region, 0)
            dwm.DwmEnableBlurBehindWindow(handle, behind)
            gdi.DeleteObject(region)
        end)
        if not ok then
            io.stderr:write('Transparent window unavailable: ', tostring(message), '\n')
        end
        return ok
    end

    -- Creates another window on the main OpenGL context. flags: title, x, y, resizable,
    -- borderless, alwaysontop, hidden. Returns a record { raw, id, listener } or nil, message.
    function Platform:createWindow(width, height, flags)
        flags = flags or {}
        assert(self.window and self.context, 'Open the main window before creating another one')
        local sdl = self.sdl
        local bit = require('bit')
        local windowFlags = bit.bor(K.OPENGL, K.HIGHDPI)
        windowFlags = bit.bor(windowFlags, flags.hidden and 0 or K.SHOWN)
        for flag, value in pairs({
            resizable = K.RESIZABLE,
            borderless = K.BORDERLESS,
            alwaysontop = K.ALWAYS_ON_TOP,
        }) do
            if flags[flag] then
                windowFlags = bit.bor(windowFlags, value)
            end
        end
        local raw = sdl.SDL_CreateWindow(
            flags.title or 'Katsa',
            flags.x or K.CENTERED,
            flags.y or K.CENTERED,
            width,
            height,
            windowFlags
        )
        if raw == nil then
            return nil, 'Could not create window: ' .. ffi.string(sdl.SDL_GetError())
        end
        local record = { raw = raw, id = sdl.SDL_GetWindowID(raw) }
        self.subWindows = self.subWindows or {}
        self.subWindows[record.id] = record
        -- Present without waiting: the main loop already paces the frame.
        self:bind(raw)
        sdl.SDL_GL_SetSwapInterval(0)
        self:bind(self.mainWindow or self.window)
        if flags.opacity then
            sdl.SDL_SetWindowOpacity(raw, flags.opacity)
        end
        if flags.minwidth and flags.minheight then
            sdl.SDL_SetWindowMinimumSize(raw, flags.minwidth, flags.minheight)
        end
        -- Owned by the main window unless `owner = false`: it stays above it without topmost.
        if flags.owner ~= false and not flags.alwaysontop then
            record.owned = self:setOwner(raw, self.mainWindow or self.window)
        end
        if flags.fullscreen then
            sdl.SDL_SetWindowFullscreen(
                raw,
                flags.fullscreen == 'exclusive' and K.FULLSCREEN or K.FULLSCREEN_DESKTOP
            )
        end
        return record
    end

    -- Makes `raw` the window every other platform call refers to, and its drawable current.
    function Platform:bind(raw)
        self.mainWindow = self.mainWindow or self.window
        self.window = raw
        self.sdl.SDL_GL_MakeCurrent(raw, self.context)
        -- The interval belongs to the drawable on some drivers and to the context on others, so it
        -- is stated at every switch: extra windows present at once, the main one follows vsync.
        -- Otherwise each extra window's swap could wait a whole refresh and stall the frame.
        if raw ~= self.mainWindow then
            self.sdl.SDL_GL_SetSwapInterval(0)
        elseif self.vsync then
            self.sdl.SDL_GL_SetSwapInterval(self.vsync)
        end
    end

    local function log(message)
        require('source.katsa.core.log').write('log', message, 'window', true)
    end

    -- Destroys an SDL window that no record owns any more. Each step is logged (silently, in the
    -- history and the log file): a freeze while closing windows shows which call it stopped in.
    local function destroyRaw(self, raw, id)
        local sdl, main = self.sdl, self.mainWindow or self.window
        -- Never destroy the window that owns the current context or the call target.
        if self.window == raw then
            self:bind(main)
        end
        log('window ' .. tostring(id) .. ': context to main')
        sdl.SDL_GL_MakeCurrent(main, self.context)
        log('window ' .. tostring(id) .. ': hide')
        sdl.SDL_HideWindow(raw)
        log('window ' .. tostring(id) .. ': destroy')
        sdl.SDL_DestroyWindow(raw)
        log('window ' .. tostring(id) .. ': raise main')
        sdl.SDL_RaiseWindow(main)
        sdl.SDL_SetWindowInputFocus(main)
        log('window ' .. tostring(id) .. ': closed')
    end

    function Platform:destroyWindow(record)
        local raw = record.raw
        if not raw then
            return
        end
        self.subWindows[record.id] = nil
        record.listener = nil
        record.raw = nil
        if self.liveResizing then
            -- Inside the OS's own move/size loop (a frame run from an event watch): destroying a
            -- window from here would pull it out from under the event being dispatched. Hide it
            -- now and destroy it when the loop is over.
            self.sdl.SDL_HideWindow(raw)
            self.closedWindows = self.closedWindows or {}
            self.closedWindows[#self.closedWindows + 1] = { raw = raw, id = record.id }
            return
        end
        destroyRaw(self, raw, record.id)
    end

    -- Destroys the windows whose closing was deferred; run at the start of every event poll, never
    -- from inside a watch.
    function Platform:flushClosedWindows()
        local list = self.closedWindows
        if not list or #list == 0 or self.liveResizing then
            return
        end
        self.closedWindows = {}
        for _, entry in ipairs(list) do
            destroyRaw(self, entry.raw, entry.id)
        end
    end

    -- Events of other windows go to their record's `listener(name, ...)`; a close request marks the
    -- window closed instead of quitting. Returns true when the event belonged to another window.
    function Platform:routeSubWindowEvent(e)
        local t, EVENT = e.type, K.EVENT
        local id
        if t == EVENT.WINDOW then
            id = e.window.windowID
        elseif t == EVENT.MOUSEMOTION then
            id = e.motion.windowID
        elseif t == EVENT.MOUSEBUTTONDOWN or t == EVENT.MOUSEBUTTONUP then
            id = e.button.windowID
        elseif t == EVENT.MOUSEWHEEL then
            id = e.wheel.windowID
        elseif t == EVENT.KEYDOWN or t == EVENT.KEYUP then
            id = e.key.windowID
        elseif t == EVENT.TEXTINPUT then
            id = e.text.windowID
        end
        local record = id and self.subWindows[id]
        if not record then
            return false
        end
        local listener = record.listener
        if t == EVENT.WINDOW then
            local kind = e.window.event
            if kind == K.WINDOW_EVENT.CLOSE then
                record.closeRequested = true
                if listener then
                    listener('close')
                end
            elseif kind == K.WINDOW_EVENT.FOCUS_GAINED or kind == K.WINDOW_EVENT.FOCUS_LOST then
                record.focused = kind == K.WINDOW_EVENT.FOCUS_GAINED
                if listener then
                    listener('focus', record.focused)
                end
            elseif kind == K.WINDOW_EVENT.MINIMIZED or kind == K.WINDOW_EVENT.HIDDEN then
                record.visible = false
            elseif kind == K.WINDOW_EVENT.RESTORED or kind == K.WINDOW_EVENT.SHOWN then
                record.visible = true
            end
        elseif listener then
            -- Pointer coordinates are in the window's own units (raw pixels / UI scale).
            local scale = 1
            if t ~= EVENT.KEYDOWN and t ~= EVENT.KEYUP and t ~= EVENT.TEXTINPUT then
                local previous = self.window
                self:target(record.raw)
                scale = self:getUIScale(self:getShortSide())
                self:target(previous)
            end
            if t == EVENT.KEYDOWN or t == EVENT.KEYUP then
                local key, scancode = require('source.katsa.platform.sdl2keys').fromSDL(
                    e.key.keysym.sym,
                    e.key.keysym.scancode
                )
                if t == EVENT.KEYDOWN then
                    listener('keypressed', key, scancode, e.key.repeat_ ~= 0)
                else
                    listener('keyreleased', key, scancode)
                end
            elseif t == EVENT.TEXTINPUT then
                listener('textinput', ffi.string(e.text.text))
            elseif t == EVENT.MOUSEMOTION then
                listener(
                    'mousemoved',
                    e.motion.x / scale,
                    e.motion.y / scale,
                    e.motion.xrel / scale,
                    e.motion.yrel / scale
                )
            elseif t == EVENT.MOUSEBUTTONDOWN or t == EVENT.MOUSEBUTTONUP then
                local button = e.button.button
                local mapped = button == 1 and 1 or button == 3 and 2 or button == 2 and 3 or button
                listener(
                    t == EVENT.MOUSEBUTTONDOWN and 'mousepressed' or 'mousereleased',
                    e.button.x / scale,
                    e.button.y / scale,
                    mapped
                )
            elseif t == EVENT.MOUSEWHEEL then
                listener('wheelmoved', e.wheel.x, e.wheel.y)
            end
        end
        return true
    end
end
