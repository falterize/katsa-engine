-- Events of a window that no longer exists must not reach the game as main-window events.
local ffi = require('ffi')
local Module = {}

function Module.run(self)
    local platform = katsa.platform
    local sdl = platform.sdl
    local event = ffi.new('SDL_Event')
    local function windowEvent(id, kind)
        ffi.fill(event, ffi.sizeof(event))
        event.type = 0x200 -- SDL_WINDOWEVENT
        event.window.windowID = id
        event.window.event = kind
        return platform:translate(event)
    end
    local mainId = sdl.SDL_GetWindowID(platform.mainWindow or platform.window)
    local W = { HIDDEN = 2, FOCUS_GAINED = 12, FOCUS_LOST = 13, CLOSE = 14 }
    self:check(windowEvent(mainId + 100, W.HIDDEN) == nil, 'A closed window being hidden is ignored')
    self:check(windowEvent(mainId + 100, W.FOCUS_LOST) == nil, 'A closed window losing focus is ignored')
    self:check(windowEvent(mainId + 100, W.CLOSE) == nil, 'A closed window close request does not quit the game')
    local translated = windowEvent(mainId, W.FOCUS_LOST)
    self:check(translated and translated[1] == 'focus' and translated[2] == false, 'The main window focus loss still reaches the game')
    windowEvent(mainId, W.FOCUS_GAINED)
end

return Module
