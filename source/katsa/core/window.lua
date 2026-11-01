-- katsa.window: window creation and queries (love.window compatible subset).
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

function Window.close()
    if platform and platform.window then
        platform:close()
        mode.open = false
    end
end

return Window
