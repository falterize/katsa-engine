-- katsa.window: window creation and queries.
local Window = {}

local platform
local mode = { open = false }
local hooks = {}

function Window.setPlatform(p)
    platform = p
end

-- Called after a window (re)creation so graphics can rebuild its default framebuffer state.
function Window.onModeSet(fn)
    hooks[#hooks + 1] = fn
end

local function normalizeFlags(flags)
    flags = flags or {}
    local normalized = {}
    for key, value in pairs(flags) do
        normalized[key] = value
    end
    if normalized.fullscreen == true then
        local exclusive = normalized.fullscreentype == 'exclusive'
        normalized.fullscreen = exclusive and 'exclusive' or 'desktop'
    elseif normalized.fullscreen == false then
        normalized.fullscreen = nil
    end
    if normalized.vsync == true then
        normalized.vsync = 1
    elseif normalized.vsync == false then
        normalized.vsync = 0
    end
    return normalized
end

function Window.setMode(width, height, flags)
    assert(platform, 'No platform backend is active')
    local normalized = normalizeFlags(flags)
    local ok, message = platform:setMode(width, height, normalized)
    if not ok then
        return false, message
    end
    mode.open = true
    mode.flags = normalized
    for _, hook in ipairs(hooks) do
        hook(width, height, normalized)
    end
    return true
end

function Window.isOpen()
    return mode.open
end

function Window.getMode()
    local w, h = platform:getMode()
    local f = mode.flags or {}
    return w, h, {
        fullscreen = f.fullscreen ~= nil,
        fullscreentype = f.fullscreen == 'exclusive' and 'exclusive' or 'desktop',
        vsync = platform.vsync or 0,
        msaa = f.msaa or 0,
        stencil = f.stencil ~= false,
        depth = f.depth or 24,
        resizable = f.resizable == true,
        borderless = f.borderless == true,
        centered = f.x == nil,
        display = 1,
        minwidth = f.minwidth or 1,
        minheight = f.minheight or 1,
        highdpi = f.highdpi ~= false,
        x = f.x or 0,
        y = f.y or 0,
    }
end

function Window.getDimensions()
    local w, h = platform:getMode()
    return w, h
end

function Window.getWidth()
    return (platform:getMode())
end

function Window.getHeight()
    local _, h = platform:getMode()
    return h
end

function Window.getSafeArea()
    return platform:getSafeArea()
end

function Window.hasFocus()
    return platform ~= nil and platform:hasFocus()
end

function Window.isVisible()
    return platform ~= nil and platform:isVisible()
end

function Window.setVSync(interval)
    if type(interval) == 'boolean' then
        interval = interval and 1 or 0
    end
    platform:setVSync(interval)
end

function Window.getVSync()
    return platform.vsync or 0
end

function Window.setTitle(title)
    platform:setTitle(title)
end

function Window.getTitle()
    return platform.config.title or ''
end

function Window.getDPIScale()
    return platform:getDPIScale()
end

function Window.toPixels(x, y)
    local scale = platform:getDPIScale()
    return x * scale, y and y * scale or nil
end

function Window.fromPixels(x, y)
    local scale = platform:getDPIScale()
    return x / scale, y and y / scale or nil
end

-- Creates another window on the same graphics context. flags: title, x, y, resizable, borderless,
-- alwaysontop, hidden, opacity, fullscreen, minwidth/minheight, owner (default true: the window
-- stays above the main window without being topmost). Returns the window, or nil and a message.
function Window.create(width, height, flags)
    assert(platform and mode.open, 'Open the main window before creating another one')
    local record, message = platform:createWindow(width, height, flags)
    if not record then
        return nil, message
    end
    return require('./subWindow').new(platform, record, flags and flags.title)
end

-- Displays: raw-pixel bounds of display `index` (0 based, the primary by default) as x, y, width,
-- height, or nil for an unknown display. getDesktopSize() is the primary display's width, height.
function Window.getDisplayCount()
    return platform:getDisplayCount()
end

function Window.getDisplayBounds(index)
    return platform:getDisplayBounds(index)
end

function Window.getDesktopSize()
    local _, _, width, height = platform:getDisplayBounds(0)
    return width, height
end

-- Opacity of the main window (0..1); with the `transparent` window flag the framebuffer also
-- keeps alpha, so a background cleared with alpha 0 shows the desktop where the compositor allows.
function Window.setOpacity(opacity)
    return platform:setOpacity(opacity)
end

function Window.getOpacity()
    return platform:getOpacity()
end

-- Moves several windows at once: `moves` is a list of { window, x, y } where `window` is a window
-- from `Window.create`. Cheaper than separate setPosition calls on Windows. Returns whether the
-- OS batch was used.
function Window.moveWindows(moves)
    local list = {}
    for _, move in ipairs(moves) do
        local record = move[1]._record
        assert(record and record.raw, 'The window is closed')
        list[#list + 1] = { record.raw, move[2], move[3] }
    end
    return platform:moveWindows(list)
end

function Window.setPosition(x, y)
    platform:setPosition(x, y)
end

function Window.getPosition()
    return platform:getPosition()
end

-- Window state of the main window, named after Godot's DisplayServer. Sizes are raw pixels.
function Window.setSize(width, height)
    platform:setSize(width, height)
end

function Window.getSize()
    return platform:getRawMode()
end

function Window.getMinimumSize()
    return platform:getMinimumSize()
end

-- The title bar and frame; false gives a borderless window.
function Window.setBorderless(borderless)
    platform:setBordered(not borderless)
end

function Window.isBorderless()
    return not platform:isBordered()
end

function Window.setResizable(resizable)
    platform:setResizable(resizable)
end

function Window.isResizable()
    return platform:isResizable()
end

-- mode: false/true or 'desktop' (borderless at desktop size) / 'exclusive'.
function Window.setFullscreen(mode)
    return platform:setFullscreen(mode)
end

function Window.isFullscreen()
    return platform:isFullscreen()
end

-- The current mode: false, 'desktop' or 'exclusive' (truthy whenever fullscreen is on).
function Window.getFullscreen()
    return platform:getFullscreen()
end

function Window.toggleFullscreen()
    Window.setFullscreen(not Window.isFullscreen())
    return Window.isFullscreen()
end

function Window.setAlwaysOnTop(onTop)
    return platform:setAlwaysOnTop(onTop)
end

function Window.center()
    platform:center()
end

-- Lets the desktop show through where the frame is cleared with alpha 0 (see guides/katsa/windows).
function Window.setTransparent(enabled)
    return platform:setTransparent(enabled)
end

function Window.close()
    if platform and platform.window then
        platform:close()
        mode.open = false
    end
end

return Window
