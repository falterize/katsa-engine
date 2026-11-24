-- Touch input as Android delivers it: finger events and the mouse events SDL synthesizes from them.
local ffi = require('ffi')

ffi.cdef('int SDL_PushEvent(SDL_Event* event);')

local Module = {}

local FINGERDOWN, FINGERUP, FINGERMOTION = 0x700, 0x701, 0x702
local MOUSEBUTTONDOWN, MOUSEBUTTONUP = 0x401, 0x402

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

    -- A finger that moves several times between two polls is delivered as one move.
    for step = 1, 4 do
        push(platform, function(e)
            e.tfinger.type, e.tfinger.fingerId = FINGERMOTION, 9
            e.tfinger.x, e.tfinger.y, e.tfinger.dx, e.tfinger.dy = 0.1 * step, 0.5, 0.1, 0
        end)
    end
    push(platform, function(e)
        e.tfinger.type, e.tfinger.fingerId = FINGERUP, 9
    end)
    local moves, order = {}, {}
    for event in platform:poll() do
        order[#order + 1] = event[1]
        if event[1] == 'touchmoved' then
            moves[#moves + 1] = event
        end
    end
    self:check(#moves == 1, 'Moves of one finger within a poll merge into one: ' .. #moves)
    self:check(
        order[1] == 'touchmoved' and order[2] == 'touchreleased',
        'The merged move arrives before the release: ' .. table.concat(order, ',')
    )
    -- Moves arriving after the first one of a poll wait for the next poll (a drag cannot keep one
    -- frame busy), and a release flushes them first so no move follows it.
    push(platform, function(e)
        e.tfinger.type, e.tfinger.fingerId, e.tfinger.x, e.tfinger.dx = FINGERMOTION, 11, 0.2, 0.1
    end)
    local first = platform:poll()()
    local count = 0
    for event in platform:poll() do
        count = count + 1
    end
    self:check(first and first[1] == 'touchmoved' and count == 0, 'A single move is delivered once')
    local w = katsa.platform:getMode()
    self:check(
        moves[1] and math.abs(moves[1][5] - 0.4 * w) < 1 and math.abs(moves[1][3] - 0.4 * w) < 1,
        'The merged move keeps the latest position and the summed delta'
    )
end

return Module
