-- Runs from conf.lua, before SDL creates the first native window.
local Display = {}
local ffi, user

local function windowHandle()
    local handle = user.GetActiveWindow()
    if handle ~= nil then
        Display.window = handle
    end
    if Display.window and user.IsWindow(Display.window) ~= 0 then
        return Display.window
    end
    -- Enumerate this thread only; never inspect or select another application's window.
    local callback = ffi.cast('int (__stdcall *)(void *, intptr_t)', function(value)
        if user.IsWindowVisible(value) ~= 0 then
            Display.window = value
            return 0
        end
        return 1
    end)
    user.EnumThreadWindows(ffi.C.GetCurrentThreadId(), callback, 0)
    callback:free()
    return Display.window
end

if jit then
    jit.off(windowHandle, true)
end

function Display.initialize()
    if Display.initialized then
        return
    end
    Display.initialized = true
    ffi = require('ffi')
    if ffi.os ~= 'Windows' then
        return
    end
    ffi.cdef([[
        int __stdcall SetProcessDpiAwarenessContext(void *context);
        void *__stdcall SetThreadDpiAwarenessContext(void *context);
        int __stdcall SetProcessDPIAware(void);
        unsigned int __stdcall GetCurrentThreadId(void);
        void *__stdcall GetActiveWindow(void);
        int __stdcall IsWindow(void *window);
        int __stdcall IsWindowVisible(void *window);
        int __stdcall EnumThreadWindows(unsigned int thread, int (__stdcall *callback)(void *, intptr_t), intptr_t data);
        unsigned int __stdcall GetDpiForWindow(void *window);
        unsigned int __stdcall GetDpiForSystem(void);
        void *__stdcall GetDC(void *window);
        int __stdcall ReleaseDC(void *window, void *context);
        int __stdcall GetDeviceCaps(void *context, int index);
        int __stdcall SystemParametersInfoW(unsigned int action, unsigned int parameter, void *value, unsigned int flags);
    ]])
    user = ffi.load('user32')
    local context = ffi.cast('void *', -4) -- DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2.
    local ok, enabled = pcall(function()
        return user.SetProcessDpiAwarenessContext(context) ~= 0
    end)
    if ok and enabled then
        return
    end
    -- Hosts may have fixed process awareness already; only override our window thread.
    local threadOK, previous = pcall(function()
        return user.SetThreadDpiAwarenessContext(context)
    end)
    if threadOK and previous ~= nil then
        return
    end
    -- Older Windows versions lack per-monitor-v2 APIs, but support system awareness.
    pcall(function()
        user.SetProcessDPIAware()
    end)
end

function Display.systemScale()
    if not user then
        return 1
    end
    local ok, dpi = pcall(function()
        local handle = windowHandle()
        return handle and user.GetDpiForWindow(handle) or user.GetDpiForSystem()
    end)
    if not ok or dpi <= 0 then
        ok, dpi = pcall(function()
            return user.GetDpiForSystem()
        end)
    end
    if not ok or dpi <= 0 then
        ok, dpi = pcall(function()
            local context = user.GetDC(nil)
            if context == nil then
                return 96
            end
            local value = ffi.load('gdi32').GetDeviceCaps(context, 88) -- LOGPIXELSX.
            user.ReleaseDC(nil, context)
            return value
        end)
    end
    return ok and dpi > 0 and dpi / 96 or 1
end

function Display.initialSize(width, height)
    local scale = Display.systemScale()
    width, height = math.floor(width * scale + 0.5), math.floor(height * scale + 0.5)
    if user then
        local work = ffi.new('long[4]')
        if user.SystemParametersInfoW(48, 0, work, 0) ~= 0 then -- SPI_GETWORKAREA.
            width = math.min(width, math.max(1, tonumber(work[2] - work[0]) - 32 * scale))
            height = math.min(height, math.max(1, tonumber(work[3] - work[1]) - 64 * scale))
        end
    end
    return math.floor(width), math.floor(height)
end

function Display.uiScale()
    if not user then
        return 1
    end
    -- SDL on Windows may expose native pixels with graphics DPI 1. Compensate
    -- exactly once; platforms already exposing logical coordinates need no extra scale.
    return Display.systemScale() / katsa.graphics.getDPIScale()
end

function Display.update(dt)
    Display.elapsed = (Display.elapsed or 0) + dt
    if not user or Display.elapsed < 0.5 then
        return false
    end
    Display.elapsed = 0
    local scale = Display.uiScale()
    local changed = Display.previousScale ~= nil and Display.previousScale ~= scale
    Display.previousScale = scale
    return changed
end

return Display
