-- SDL2 platform backend: window, OpenGL context, input events, clipboard, display metrics.
-- One code path serves Windows, Linux, macOS and Android; GLES 3.0 is requested on Android.
--
-- Backend contract (shared with any future backend such as GLFW or headless):
--   Platform.new(config) -> platform | nil, message
-- platform:setMode(w, h, flags) -> true | nil, message create/resize the window and GL context
--   platform:getMode() -> w, h, flags
--   platform:getDrawableSize() -> pixel width, pixel height
--   platform:getDPIScale() -> number
--   platform:getSafeArea() -> x, y, w, h
--   platform:swap(), platform:setVSync(n), platform:getProcAddress(name)
--   platform:poll() -> iterator of event tables { name, ... } already translated to katsa events
--   platform:getTicks(), platform:setTitle(s), platform:hasFocus(), platform:isVisible()
--   platform:setRelativeMouse(b), platform:getRelativeMouse(), platform:getMousePosition()
-- platform:setTextInput(b), platform:getClipboard(), platform:setClipboard(s), platform:openURL(u)
--   platform:getPrefPath(org, app), platform:close()
local ffi = require('ffi')
local bit = require('bit')
local Native = require('source.katsa.core.native')
local Keys = require('source.katsa.platform.sdl2keys')

ffi.cdef([[
typedef struct SDL_Window SDL_Window;
typedef void* SDL_GLContext;
typedef struct { int32_t x, y, w, h; } SDL_Rect;
typedef struct { uint32_t type; uint32_t timestamp; } SDL_CommonEvent;
typedef struct { uint32_t type, timestamp, windowID; uint8_t event, padding1, padding2, padding3; int32_t data1, data2; } SDL_WindowEvent;
typedef struct { int32_t scancode; int32_t sym; uint16_t mod; uint32_t unused; } SDL_Keysym;
typedef struct { uint32_t type, timestamp, windowID; uint8_t state, repeat_, padding2, padding3; SDL_Keysym keysym; } SDL_KeyboardEvent;
typedef struct { uint32_t type, timestamp, windowID; char text[32]; } SDL_TextInputEvent;
typedef struct { uint32_t type, timestamp, windowID, which, state; int32_t x, y, xrel, yrel; } SDL_MouseMotionEvent;
typedef struct { uint32_t type, timestamp, windowID, which; uint8_t button, state, clicks, padding1; int32_t x, y; } SDL_MouseButtonEvent;
typedef struct { uint32_t type, timestamp, windowID, which; int32_t x, y; uint32_t direction; float preciseX, preciseY; int32_t mouseX, mouseY; } SDL_MouseWheelEvent;
typedef struct { uint32_t type, timestamp; int64_t touchId, fingerId; float x, y, dx, dy, pressure; uint32_t windowID; } SDL_TouchFingerEvent;
typedef struct { uint32_t type, timestamp; char* file; uint32_t windowID; } SDL_DropEvent;
typedef union {
    uint32_t type;
    SDL_CommonEvent common;
    SDL_WindowEvent window;
    SDL_KeyboardEvent key;
    SDL_TextInputEvent text;
    SDL_MouseMotionEvent motion;
    SDL_MouseButtonEvent button;
    SDL_MouseWheelEvent wheel;
    SDL_TouchFingerEvent tfinger;
    SDL_DropEvent drop;
    uint8_t padding[56];
} SDL_Event;

int SDL_Init(uint32_t flags);
void SDL_Quit(void);
const char* SDL_GetError(void);
SDL_Window* SDL_CreateWindow(const char* title, int x, int y, int w, int h, uint32_t flags);
void SDL_DestroyWindow(SDL_Window* window);
void SDL_SetWindowTitle(SDL_Window* window, const char* title);
void SDL_SetWindowSize(SDL_Window* window, int w, int h);
void SDL_SetWindowPosition(SDL_Window* window, int x, int y);
void SDL_SetWindowMinimumSize(SDL_Window* window, int w, int h);
int SDL_SetWindowFullscreen(SDL_Window* window, uint32_t flags);
void SDL_GetWindowSize(SDL_Window* window, int* w, int* h);
uint32_t SDL_GetWindowFlags(SDL_Window* window);
void SDL_GL_GetDrawableSize(SDL_Window* window, int* w, int* h);
SDL_GLContext SDL_GL_CreateContext(SDL_Window* window);
void SDL_GL_DeleteContext(SDL_GLContext context);
int SDL_GL_MakeCurrent(SDL_Window* window, SDL_GLContext context);
int SDL_GL_SetAttribute(int attr, int value);
int SDL_GL_SetSwapInterval(int interval);
void* SDL_GL_GetProcAddress(const char* proc);
void SDL_GL_SwapWindow(SDL_Window* window);
typedef int (*SDL_EventFilter)(void* userdata, SDL_Event* event);
void SDL_AddEventWatch(SDL_EventFilter filter, void* userdata);
int SDL_PollEvent(SDL_Event* event);
int SDL_WaitEventTimeout(SDL_Event* event, int timeout);
uint32_t SDL_GetTicks(void);
int SDL_GetDisplayUsableBounds(int index, SDL_Rect* rect);
int SDL_GetDisplayBounds(int index, SDL_Rect* rect);
int SDL_GetDisplayDPI(int index, float* ddpi, float* hdpi, float* vdpi);
int SDL_SetRelativeMouseMode(int enabled);
int SDL_GetRelativeMouseMode(void);
uint32_t SDL_GetMouseState(int* x, int* y);
void SDL_StartTextInput(void);
void SDL_StopTextInput(void);
void SDL_SetTextInputRect(const SDL_Rect* rect);
char* SDL_GetClipboardText(void);
int SDL_SetClipboardText(const char* text);
int SDL_OpenURL(const char* url);
int SDL_SetWindowOpacity(SDL_Window* window, float opacity);
int SDL_GetWindowOpacity(SDL_Window* window, float* opacity);
void SDL_GetWindowPosition(SDL_Window* window, int* x, int* y);
void SDL_SetWindowPosition(SDL_Window* window, int x, int y);
uint32_t SDL_GetWindowID(SDL_Window* window);
void SDL_HideWindow(SDL_Window* window);
void SDL_ShowWindow(SDL_Window* window);
void SDL_RaiseWindow(SDL_Window* window);
void SDL_SetWindowBordered(SDL_Window* window, int bordered);
void SDL_SetWindowResizable(SDL_Window* window, int resizable);
void SDL_SetWindowAlwaysOnTop(SDL_Window* window, int onTop);
int SDL_SetWindowModalFor(SDL_Window* modal, SDL_Window* parent);
void SDL_MinimizeWindow(SDL_Window* window);
void SDL_MaximizeWindow(SDL_Window* window);
void SDL_RestoreWindow(SDL_Window* window);
int SDL_SetWindowInputFocus(SDL_Window* window);
int SDL_GetWindowDisplayIndex(SDL_Window* window);
void SDL_GetWindowMinimumSize(SDL_Window* window, int* w, int* h);
void SDL_GetVersion(uint8_t* version);
typedef struct { uint8_t major, minor, patch; } SDL_version;
typedef struct { SDL_version version; int subsystem; union { struct { void* window; void* hdc; void* hinstance; } win; uint8_t dummy[64]; } info; } SDL_SysWMinfo;
int SDL_GetWindowWMInfo(SDL_Window* window, SDL_SysWMinfo* info);
void SDL_free(void* memory);
char* SDL_GetPrefPath(const char* org, const char* app);
const char* SDL_GetPlatform(void);
int SDL_GetNumVideoDisplays(void);
void SDL_SetHint(const char* name, const char* value);
int SDL_ShowCursor(int toggle);
void SDL_WarpMouseInWindow(SDL_Window* window, int x, int y);
void SDL_SetWindowGrab(SDL_Window* window, int grabbed);
int SDL_GetWindowGrab(SDL_Window* window);
typedef struct SDL_Cursor SDL_Cursor;
SDL_Cursor* SDL_CreateSystemCursor(int id);
void SDL_SetCursor(SDL_Cursor* cursor);
void SDL_FreeCursor(SDL_Cursor* cursor);
int SDL_GetCPUCount(void);
const uint8_t* SDL_GetKeyboardState(int* numkeys);
]])

local SDL_INIT_VIDEO, SDL_INIT_EVENTS = 0x20, 0x4000
local WINDOW_FULLSCREEN, WINDOW_OPENGL, WINDOW_SHOWN, WINDOW_HIDDEN = 0x1, 0x2, 0x4, 0x8
local WINDOW_BORDERLESS, WINDOW_RESIZABLE, WINDOW_MINIMIZED = 0x10, 0x20, 0x40
local WINDOW_MAXIMIZED, WINDOW_INPUT_FOCUS, WINDOW_ALLOW_HIGHDPI = 0x80, 0x200, 0x2000
local WINDOW_FULLSCREEN_DESKTOP = 0x1001
local WINDOW_ALWAYS_ON_TOP = 0x8000
local CENTERED = 0x2FFF0000

local ATTR = {
    RED = 0, GREEN = 1, BLUE = 2, ALPHA = 3, DOUBLEBUFFER = 5, DEPTH = 6, STENCIL = 7,
    MULTISAMPLEBUFFERS = 13, MULTISAMPLESAMPLES = 14,
    MAJOR = 17, MINOR = 18, FLAGS = 20, PROFILE = 21, SHARE = 22, FRAMEBUFFER_SRGB = 23,
}
local PROFILE_CORE, PROFILE_ES = 1, 4

local EVENT = {
    QUIT = 0x100, WINDOW = 0x200, KEYDOWN = 0x300, KEYUP = 0x301, TEXTINPUT = 0x303,
    MOUSEMOTION = 0x400, MOUSEBUTTONDOWN = 0x401, MOUSEBUTTONUP = 0x402, MOUSEWHEEL = 0x403,
    FINGERDOWN = 0x700, FINGERUP = 0x701, FINGERMOTION = 0x702, DROPFILE = 0x1000,
    LOWMEMORY = 0x106,
}
local WINDOW_EVENT = {
    SHOWN = 1, HIDDEN = 2, EXPOSED = 3, MOVED = 4, RESIZED = 5, SIZE_CHANGED = 6, MINIMIZED = 7,
    MAXIMIZED = 8, RESTORED = 9, ENTER = 10, LEAVE = 11, FOCUS_GAINED = 12, FOCUS_LOST = 13,
    CLOSE = 14,
}

local Platform = {}
Platform.__index = Platform

local MODAL_AFTER_MS = 30 -- a poll call longer than this is the OS running its own move/size loop
local MODAL_FRAME_MS = 8 -- at most one frame per this many ms from inside that loop

local function sdlError(sdl)
    return ffi.string(sdl.SDL_GetError())
end

function Platform.new(config)
    local sdl, message = Native.load('SDL2')
    if not sdl then
        return nil, message
    end
    sdl.SDL_SetHint('SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR', '0')
    if sdl.SDL_Init(bit.bor(SDL_INIT_VIDEO, SDL_INIT_EVENTS)) ~= 0 then
        return nil, 'SDL_Init failed: ' .. sdlError(sdl)
    end
    local self = setmetatable({
        sdl = sdl,
        config = config or {},
        event = ffi.new('SDL_Event'),
        pending = {},
        focus = true,
        visible = true,
        textInput = false,
        mouseX = 0,
        mouseY = 0,
        es = Native.os() == 'Android' or (config and config.gles) == true,
        rects = { ffi.new('int[1]'), ffi.new('int[1]') },
    }, Platform)
    return self
end

function Platform:getName()
    return ffi.string(self.sdl.SDL_GetPlatform())
end

-- flags: resizable, borderless, fullscreen ('desktop' | 'exclusive'), minwidth, minheight, vsync,
-- msaa, depth, stencil, highdpi, x, y, centered, title, srgb
function Platform:setMode(width, height, flags)
    flags = flags or {}
    local sdl = self.sdl
    local existing = self.window ~= nil
    if existing then
        local scale = self:getUIScale(self:getShortSide())
        sdl.SDL_SetWindowSize(self.window, width * scale, height * scale)
        if flags.borderless == nil then
            -- keep current decorations
        end
        if flags.fullscreen then
            sdl.SDL_SetWindowFullscreen(
                self.window,
                flags.fullscreen == 'exclusive' and WINDOW_FULLSCREEN or WINDOW_FULLSCREEN_DESKTOP
            )
        else
            sdl.SDL_SetWindowFullscreen(self.window, 0)
        end
        if flags.minwidth and flags.minheight then
            sdl.SDL_SetWindowMinimumSize(self.window, flags.minwidth, flags.minheight)
        end
        if flags.x and flags.y then
            sdl.SDL_SetWindowPosition(self.window, flags.x, flags.y)
        elseif flags.centered ~= false then
            sdl.SDL_SetWindowPosition(self.window, CENTERED, CENTERED)
        end
        self.flags = flags
        self:setVSync(flags.vsync == nil and 1 or flags.vsync)
        return true
    end
    if self.es then
        sdl.SDL_GL_SetAttribute(ATTR.MAJOR, 3)
        sdl.SDL_GL_SetAttribute(ATTR.MINOR, 0)
        sdl.SDL_GL_SetAttribute(ATTR.PROFILE, PROFILE_ES)
    else
        sdl.SDL_GL_SetAttribute(ATTR.MAJOR, 3)
        sdl.SDL_GL_SetAttribute(ATTR.MINOR, 3)
        sdl.SDL_GL_SetAttribute(ATTR.PROFILE, PROFILE_CORE)
    end
    sdl.SDL_GL_SetAttribute(ATTR.DOUBLEBUFFER, 1)
    sdl.SDL_GL_SetAttribute(ATTR.DEPTH, flags.depth or 24)
    sdl.SDL_GL_SetAttribute(ATTR.STENCIL, flags.stencil or 8)
    sdl.SDL_GL_SetAttribute(ATTR.MULTISAMPLEBUFFERS, (flags.msaa or 0) > 0 and 1 or 0)
    sdl.SDL_GL_SetAttribute(ATTR.MULTISAMPLESAMPLES, flags.msaa or 0)
    sdl.SDL_GL_SetAttribute(ATTR.FRAMEBUFFER_SRGB, flags.srgb and 1 or 0)
    -- Destination alpha is on unless `transparent = false`, so a window can be made transparent
    -- later without recreating its context; every window shares this pixel format.
    sdl.SDL_GL_SetAttribute(ATTR.ALPHA, flags.transparent == false and 0 or 8)
    local windowFlags = bit.bor(WINDOW_OPENGL, WINDOW_SHOWN)
    if flags.highdpi ~= false then
        windowFlags = bit.bor(windowFlags, WINDOW_ALLOW_HIGHDPI)
    end
    if flags.resizable then
        windowFlags = bit.bor(windowFlags, WINDOW_RESIZABLE)
    end
    if flags.borderless then
        windowFlags = bit.bor(windowFlags, WINDOW_BORDERLESS)
    end
    if flags.alwaysontop then
        windowFlags = bit.bor(windowFlags, WINDOW_ALWAYS_ON_TOP)
    end
    if flags.fullscreen then
        windowFlags = bit.bor(
            windowFlags,
            flags.fullscreen == 'exclusive' and WINDOW_FULLSCREEN or WINDOW_FULLSCREEN_DESKTOP
        )
    end
    local x = flags.x or CENTERED
    local y = flags.y or CENTERED
    self.window = sdl.SDL_CreateWindow(flags.title or self.config.title or 'Katsa', x, y, width,
        height, windowFlags)
    if self.window == nil then
        self.window = nil
        return nil, 'Could not create window: ' .. sdlError(sdl)
    end
    self.windowID = sdl.SDL_GetWindowID(self.window)
    self.context = sdl.SDL_GL_CreateContext(self.window)
    if self.context == nil then
        local reason = sdlError(sdl)
        sdl.SDL_DestroyWindow(self.window)
        self.window = nil
        return nil, 'Could not create OpenGL context: ' .. reason
    end
    if flags.minwidth and flags.minheight then
        sdl.SDL_SetWindowMinimumSize(self.window, flags.minwidth, flags.minheight)
    end
    self.flags = flags
    self:setVSync(flags.vsync == nil and 1 or flags.vsync)
    if flags.transparent then
        self:setTransparent(true)
    end
    return true
end

function Platform:setVSync(interval)
    -- Adaptive vsync (-1) falls back to regular vsync where unsupported.
    if self.sdl.SDL_GL_SetSwapInterval(interval) ~= 0 and interval < 0 then
        self.sdl.SDL_GL_SetSwapInterval(1)
    end
    self.vsync = interval
end

-- Window units are SDL pixels divided by the UI scale. The scale is 1 on desktop unless
-- KATSA_UI_SCALE (or `uiscale` in the window flags) is set; on Android it makes the logical window
-- about ANDROID_LOGICAL_HEIGHT units on the short side (landscape height, portrait width), so
-- buttons are finger sized in both orientations. Everything above the
-- platform (layout, pointer coordinates, graphics) works in window units, exactly as with a
-- high-DPI display, because getDPIScale() reports the ratio of drawable pixels to window units.
local ANDROID_LOGICAL_HEIGHT = 540

function Platform:getUIScale(shortSide)
    local fixed = tonumber(os.getenv('KATSA_UI_SCALE')) or (self.flags and self.flags.uiscale)
    if fixed then
        return math.max(0.25, fixed)
    end
    if Native.os() == 'Android' and shortSide and shortSide > 0 then
        return math.min(3, math.max(1, shortSide / ANDROID_LOGICAL_HEIGHT))
    end
    return 1
end

function Platform:getShortSide()
    local rw, rh = self:getRawMode()
    return math.min(rw, rh)
end

function Platform:getRawMode()
    local w, h = self.rects[1], self.rects[2]
    self.sdl.SDL_GetWindowSize(self.window, w, h)
    return w[0], h[0]
end

function Platform:getMode()
    local rw, rh = self:getRawMode()
    local scale = self:getUIScale(math.min(rw, rh))
    return rw / scale, rh / scale, self.flags or {}
end

function Platform:getDrawableSize()
    local w, h = self.rects[1], self.rects[2]
    self.sdl.SDL_GL_GetDrawableSize(self.window, w, h)
    return w[0], h[0]
end

function Platform:getDPIScale()
    local w = self:getMode()
    local dw = self:getDrawableSize()
    return w > 0 and dw / w or 1
end

function Platform:getSafeArea()
    local rect = ffi.new('SDL_Rect')
    if self.sdl.SDL_GetDisplayUsableBounds(0, rect) == 0 and Native.os() == 'Android' then
        local w, h = self:getMode()
        return 0, 0, w, h
    end
    local w, h = self:getMode()
    return 0, 0, w, h
end

function Platform:getProcAddress(name)
    local pointer = self.sdl.SDL_GL_GetProcAddress(name)
    return pointer ~= nil and pointer or nil
end

function Platform:swap()
    self.sdl.SDL_GL_SwapWindow(self.window)
end

function Platform:getTicks()
    return self.sdl.SDL_GetTicks()
end

function Platform:setTitle(title)
    if self.window then
        self.sdl.SDL_SetWindowTitle(self.window, title)
    end
    self.config.title = title
end

function Platform:hasFocus()
    return self.focus
end

function Platform:isVisible()
    return self.visible
end

function Platform:setRelativeMouse(enabled)
    self.sdl.SDL_SetRelativeMouseMode(enabled and 1 or 0)
end

function Platform:getRelativeMouse()
    return self.sdl.SDL_GetRelativeMouseMode() ~= 0
end

function Platform:getMousePosition()
    local x, y = self.rects[1], self.rects[2]
    self.sdl.SDL_GetMouseState(x, y)
    -- getShortSide() reuses the same rects buffers, so copy the pointer position out first.
    local px, py = x[0], y[0]
    local scale = self:getUIScale(self:getShortSide())
    return px / scale, py / scale
end

function Platform:isScancodeDown(name)
    local code = Keys.scancodeByName[name]
    if not code then
        return false
    end
    return self.sdl.SDL_GetKeyboardState(nil)[code] ~= 0
end

-- button: katsa numbering (1 left, 2 right, 3 middle, 4/5 extra).
function Platform:isMouseDown(button)
    local mask = self.sdl.SDL_GetMouseState(nil, nil)
    local bitIndex = button == 1 and 0 or button == 2 and 2 or button == 3 and 1 or button - 1
    return bit.band(mask, bit.lshift(1, bitIndex)) ~= 0
end

function Platform:setCursorVisible(visible)
    self.sdl.SDL_ShowCursor(visible and 1 or 0)
end

function Platform:isCursorVisible()
    return self.sdl.SDL_ShowCursor(-1) == 1 -- -1 only queries
end

-- Moves the pointer; x, y are in the same units getMousePosition returns.
function Platform:setMousePosition(x, y)
    local scale = self:getUIScale(self:getShortSide())
    self.sdl.SDL_WarpMouseInWindow(self.window, math.floor(x * scale + 0.5), math.floor(y * scale + 0.5))
end

function Platform:setMouseGrab(grabbed)
    self.sdl.SDL_SetWindowGrab(self.window, grabbed and 1 or 0)
end

function Platform:getMouseGrab()
    return self.sdl.SDL_GetWindowGrab(self.window) ~= 0
end

-- SDL_SystemCursor ids by Love2D's cursor names.
local SYSTEM_CURSORS = {
    arrow = 0, ibeam = 1, wait = 2, crosshair = 3, waitarrow = 4, sizenwse = 5, sizenesw = 6,
    sizewe = 7, sizens = 8, sizeall = 9, no = 10, hand = 11,
}

-- Returns an SDL cursor that is freed with the platform's other resources; nil for unknown names.
function Platform:getSystemCursor(name)
    local id = SYSTEM_CURSORS[name]
    if not id then
        return nil
    end
    self.cursors = self.cursors or {}
    if not self.cursors[name] then
        local cursor = self.sdl.SDL_CreateSystemCursor(id)
        if cursor == nil then
            return nil
        end
        self.cursors[name] = ffi.gc(cursor, self.sdl.SDL_FreeCursor)
    end
    return self.cursors[name]
end

function Platform:setCursor(cursor)
    self.activeCursor = cursor
    self.sdl.SDL_SetCursor(cursor)
end

function Platform:setTextInput(enabled)
    if enabled then
        self.sdl.SDL_StartTextInput()
    else
        self.sdl.SDL_StopTextInput()
    end
    self.textInput = enabled
end

function Platform:getClipboard()
    local text = self.sdl.SDL_GetClipboardText()
    if text == nil then
        return ''
    end
    local value = ffi.string(text)
    self.sdl.SDL_free(text)
    return value
end

function Platform:setClipboard(text)
    self.sdl.SDL_SetClipboardText(text)
end

function Platform:openURL(url)
    return self.sdl.SDL_OpenURL(url) == 0
end

function Platform:getPrefPath(organization, application)
    local path = self.sdl.SDL_GetPrefPath(organization, application)
    if path == nil then
        return nil
    end
    local value = ffi.string(path):gsub('[\\/]+$', '')
    self.sdl.SDL_free(path)
    return value
end

function Platform:getProcessorCount()
    return self.sdl.SDL_GetCPUCount()
end

local buttonNames = { 'l', 'm', 'r', 'x1', 'x2' }
local loveButtons = { 1, 3, 2, 4, 5 } -- SDL left, middle, right, x1, x2 -> katsa 1, 3, 2 ...

-- Translates one SDL event to a katsa event table, or nil for events katsa ignores.
function Platform:translate(e)
    local t = e.type
    if self.subWindows and self:routeSubWindowEvent(e) then
        return nil
    end
    if t == EVENT.QUIT then
        return { 'quit' }
    elseif t == EVENT.KEYDOWN or t == EVENT.KEYUP then
        local key, scancode = Keys.fromSDL(e.key.keysym.sym, e.key.keysym.scancode)
        if t == EVENT.KEYDOWN then
            return { 'keypressed', key, scancode, e.key.repeat_ ~= 0 }
        end
        return { 'keyreleased', key, scancode }
    elseif t == EVENT.TEXTINPUT then
        return { 'textinput', ffi.string(e.text.text) }
    elseif t == EVENT.MOUSEMOTION then
        local touch = e.motion.which == 0xFFFFFFFF
        local scale = self:getUIScale(self:getShortSide())
        self.mouseX, self.mouseY = e.motion.x / scale, e.motion.y / scale
        return { 'mousemoved', self.mouseX, self.mouseY, e.motion.xrel / scale, e.motion.yrel / scale, touch }
    elseif t == EVENT.MOUSEBUTTONDOWN or t == EVENT.MOUSEBUTTONUP then
        local button = e.button.button
        local mapped = button == 1 and 1 or button == 3 and 2 or button == 2 and 3 or button
        local touch = e.button.which == 0xFFFFFFFF
        local scale = self:getUIScale(self:getShortSide())
        return {
            t == EVENT.MOUSEBUTTONDOWN and 'mousepressed' or 'mousereleased',
            e.button.x / scale,
            e.button.y / scale,
            mapped,
            touch,
            e.button.clicks,
        }
    elseif t == EVENT.MOUSEWHEEL then
        local flip = e.wheel.direction == 1 and -1 or 1
        return { 'wheelmoved', e.wheel.x * flip, e.wheel.y * flip }
    elseif t == EVENT.FINGERDOWN or t == EVENT.FINGERUP or t == EVENT.FINGERMOTION then
        local w, h = self:getMode()
        local id = tonumber(e.tfinger.fingerId)
        local name = 'touchmoved'
        if t == EVENT.FINGERDOWN then
            name = 'touchpressed'
        elseif t == EVENT.FINGERUP then
            name = 'touchreleased'
        end
        local finger = e.tfinger
        local x, y, dx, dy = finger.x * w, finger.y * h, finger.dx * w, finger.dy * h
        return { name, id, x, y, dx, dy, finger.pressure }
    elseif t == EVENT.DROPFILE then
        local path = ffi.string(e.drop.file)
        self.sdl.SDL_free(e.drop.file)
        return { 'filedropped', path }
    elseif t == EVENT.LOWMEMORY then
        return { 'lowmemory' }
    elseif t == EVENT.WINDOW then
        local kind = e.window.event
        if kind == WINDOW_EVENT.SIZE_CHANGED or kind == WINDOW_EVENT.RESIZED then
            local w, h = self:getMode()
            return { 'resize', w, h }
        elseif kind == WINDOW_EVENT.FOCUS_GAINED then
            self.focus = true
            return { 'focus', true }
        elseif kind == WINDOW_EVENT.FOCUS_LOST then
            self.focus = false
            return { 'focus', false }
        elseif kind == WINDOW_EVENT.MINIMIZED or kind == WINDOW_EVENT.HIDDEN then
            self.visible = false
            return { 'visible', false }
        elseif
            kind == WINDOW_EVENT.RESTORED
            or kind == WINDOW_EVENT.SHOWN
            or kind == WINDOW_EVENT.MAXIMIZED
        then
            self.visible = true
            return { 'visible', true }
        elseif kind == WINDOW_EVENT.CLOSE then
            return { 'quit' }
        end
    end
    return nil
end

-- Iterator over translated events currently queued by the OS.
function Platform:poll()
    local sdl, event = self.sdl, self.event
    return function()
        -- SDL calls event watches from inside SDL_PollEvent too; `polling` tells those deliveries
        -- (the frame loop handles them) from the ones sent while the OS runs its own resize loop.
        self.polling = true
        self.pollStarted = sdl.SDL_GetTicks()
        while sdl.SDL_PollEvent(event) ~= 0 do
            local translated = self:translate(event)
            if translated then
                self.polling = false
                return translated
            end
            self.pollStarted = sdl.SDL_GetTicks()
        end
        self.polling = false
        return nil
    end
end

-- While the user drags a window edge or its title bar, Windows (and macOS) run a modal loop inside
-- SDL_PollEvent that keeps the frame loop from running: the UI would keep the old size and the game
-- would freeze until the button is released. SDL still reports the window events to an event watch
-- on the main thread, so `handler(width, height, resized)` is called there to run and draw a frame.
-- A poll call that has lasted longer than a normal one (see MODAL_AFTER_MS) is such a loop.
function Platform:onLiveResize(handler)
    if self.liveResizeWatch then
        self.liveResizeHandler = handler
        return
    end
    self.liveResizeHandler = handler
    self.liveResizeWatch = ffi.cast('SDL_EventFilter', function(_, event)
        local kind = event.type == EVENT.WINDOW and event.window.event
        local sized = kind == WINDOW_EVENT.SIZE_CHANGED or kind == WINDOW_EVENT.RESIZED
        local moved = kind == WINDOW_EVENT.MOVED or kind == WINDOW_EVENT.EXPOSED
        local now = self.sdl.SDL_GetTicks()
        local modal = not self.polling or now - (self.pollStarted or now) > MODAL_AFTER_MS
        if
            (sized or moved)
            and modal
            and not self.liveResizing
            and now - (self.lastModalFrame or 0) >= MODAL_FRAME_MS
        then
            self.liveResizing = true
            local ok, message = pcall(self.liveResizeHandler, self:getMode())
            self.lastModalFrame = self.sdl.SDL_GetTicks()
            self.liveResizing = false
            if not ok then
                io.stderr:write('Live resize failed: ', tostring(message), '\n')
            end
        end
        return 0
    end)
    self.sdl.SDL_AddEventWatch(self.liveResizeWatch, nil)
end

function Platform:close()
    if self.context then
        self.sdl.SDL_GL_DeleteContext(self.context)
        self.context = nil
    end
    if self.window then
        self.sdl.SDL_DestroyWindow(self.window)
        self.window = nil
    end
    self.sdl.SDL_Quit()
end

-- Extra windows and per-window opacity (see sdl2windows.lua).
require('./sdl2windows')(Platform, {
    OPENGL = WINDOW_OPENGL,
    SHOWN = WINDOW_SHOWN,
    BORDERLESS = WINDOW_BORDERLESS,
    RESIZABLE = WINDOW_RESIZABLE,
    ALWAYS_ON_TOP = WINDOW_ALWAYS_ON_TOP,
    FULLSCREEN = WINDOW_FULLSCREEN,
    FULLSCREEN_DESKTOP = WINDOW_FULLSCREEN_DESKTOP,
    HIGHDPI = WINDOW_ALLOW_HIGHDPI,
    CENTERED = CENTERED,
    EVENT = EVENT,
    WINDOW_EVENT = WINDOW_EVENT,
})

return Platform
