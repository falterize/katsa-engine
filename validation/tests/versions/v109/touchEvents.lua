-- Touch input as Android delivers it: finger events and the mouse events SDL synthesizes from them.
local ffi = require('ffi')

ffi.cdef('int SDL_PushEvent(SDL_Event* event);')

local Module = {}

local FINGERDOWN, FINGERUP, MOUSEBUTTONDOWN, MOUSEBUTTONUP = 0x700, 0x701, 0x401, 0x402

local function push(platform, fill)
    local event = ffi.new('SDL_Event')
    fill(event)
    platform.sdl.SDL_PushEvent(event)
end

function Module.run(self)
    local platform = katsa.platform
    local names = {}
    push(platform, function(e)
        e.tfinger.type, e.tfinger.fingerId, e.tfinger.x, e.tfinger.y = FINGERDOWN, 7, 0.5, 0.25
    end)
    push(platform, function(e)
        e.button.type, e.button.which, e.button.button, e.button.x, e.button.y =
            MOUSEBUTTONDOWN, 0xFFFFFFFF, 1, 20, 30
    end)
    push(platform, function(e)
        e.button.type, e.button.which, e.button.button, e.button.x, e.button.y =
            MOUSEBUTTONUP, 0xFFFFFFFF, 1, 20, 30
    end)
    push(platform, function(e)
        e.tfinger.type, e.tfinger.fingerId = FINGERUP, 7
    end)
    local ok, message = pcall(function()
        for event in platform:poll() do
            names[#names + 1] = event[1]
        end
    end)
    self:check(ok, 'Polling touch events does not raise: ' .. tostring(message))
    self:check(
        table.concat(names, ',') == 'touchpressed,mousepressed,mousereleased,touchreleased',
        'Touch and synthesized mouse events are translated: ' .. table.concat(names, ',')
    )
end

return Module
