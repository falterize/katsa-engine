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

    -- Per-pixel transparency of the main window. Linux and macOS compositors honour the alpha
    -- channel of the framebuffer by themselves; on Windows the window must be told to blend with
    -- the desktop (DWM), the way GLFW does it. Returns whether the call could be made.
    function Platform:setTransparent(enabled)
        self.transparent = enabled
        if ffi.os ~= 'Windows' then
            return true
        end
        local ok, message = pcall(function()
            ffi.cdef([[
                typedef struct { uint32_t flags; int enable; void* region; int transition; } KatsaBlurBehind;
                int DwmEnableBlurBehindWindow(void* window, const KatsaBlurBehind* behind);
                void* CreateRectRgn(int left, int top, int right, int bottom);
                int DeleteObject(void* object);
            ]])
            local info = ffi.new('SDL_SysWMinfo')
            self.sdl.SDL_GetVersion(ffi.cast('uint8_t*', info.version))
            if self.sdl.SDL_GetWindowWMInfo(self.window, info) == 0 then
                error('SDL_GetWindowWMInfo failed')
            end
            local dwm, gdi = ffi.load('dwmapi'), ffi.load('gdi32')
            -- An empty blur region switches per-pixel alpha on without blurring anything.
            local region = gdi.CreateRectRgn(0, 0, -1, -1)
            local behind = ffi.new('KatsaBlurBehind', 3, enabled and 1 or 0, region, 0)
            dwm.DwmEnableBlurBehindWindow(info.info.win.window, behind)
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
        return record
    end

    -- Makes `raw` the window every other platform call refers to, and its drawable current.
    function Platform:bind(raw)
        self.mainWindow = self.mainWindow or self.window
        self.window = raw
        self.sdl.SDL_GL_MakeCurrent(raw, self.context)
    end

    function Platform:destroyWindow(record)
        if record.raw then
            self.subWindows[record.id] = nil
            self.sdl.SDL_DestroyWindow(record.raw)
            record.raw = nil
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
        end
        local record = id and self.subWindows[id]
        if not record then
            return false
        end
        local listener = record.listener
        if t == EVENT.WINDOW then
            if e.window.event == K.WINDOW_EVENT.CLOSE then
                record.closeRequested = true
                if listener then
                    listener('close')
                end
            end
        elseif listener then
            if t == EVENT.MOUSEMOTION then
                listener('mousemoved', e.motion.x, e.motion.y, e.motion.xrel, e.motion.yrel)
            elseif t == EVENT.MOUSEBUTTONDOWN or t == EVENT.MOUSEBUTTONUP then
                local button = e.button.button
                local mapped = button == 1 and 1 or button == 3 and 2 or button == 2 and 3 or button
                listener(
                    t == EVENT.MOUSEBUTTONDOWN and 'mousepressed' or 'mousereleased',
                    e.button.x,
                    e.button.y,
                    mapped
                )
            elseif t == EVENT.MOUSEWHEEL then
                listener('wheelmoved', e.wheel.x, e.wheel.y)
            end
        end
        return true
    end
end
