-- Pinch zoom follows the mouse-wheel rules: the joystick finger never counts, and a finger over an
-- interactable UI element blocks the zoom.
local Pinch = require('source.game.scenes.multiplayerCars.scripts.controller.pinch')

local Module = {}

local function fake(blocked)
    local zoomed = 0
    local session = setmetatable({
        client = {},
        touches = {},
        scene = {
            input = { joystickId = 1, playing = function() return true end },
            ui = { blocksWorldClick = function() return blocked end },
        },
        orbit = { zoom = function(_, amount) zoomed = zoomed + math.abs(amount) end },
    }, {})
    return session, function() return zoomed end
end

function Module.run(self)
    local session, zoomed = fake(false)
    session.touches[1], session.touches[2] = { 100, 500 }, { 900, 300 }
    Pinch.moved(session, 2, 700, 300)
    self:check(zoomed() == 0, 'joystick finger plus camera finger does not zoom')

    session.touches[1] = nil
    session.touches[2], session.touches[3] = { 400, 300 }, { 800, 300 }
    session.pinchLast = 400
    Pinch.moved(session, 3, 900, 300)
    self:check(zoomed() > 0, 'two free fingers pinch-zoom')

    local blocked, blockedZoom = fake(true)
    blocked.touches[2], blocked.touches[3] = { 400, 300 }, { 800, 300 }
    blocked.pinchLast = 400
    Pinch.moved(blocked, 3, 900, 300)
    self:check(blockedZoom() == 0, 'fingers over interactable UI do not zoom')
end

return Module
