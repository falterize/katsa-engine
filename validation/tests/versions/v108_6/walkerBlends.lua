-- A replicated walker's blends are extrapolated and can leave 0..1; the animation weights must not
-- (Track:advance asserts 0..1, which crashed multiplayer sessions).
local WalkerView = require('source.game.scenes.multiplayerCars.scripts.walker.view')

local Module = {}

function Module.run(self)
    local function track()
        return { weight = 0, clip = { duration = 1 }, play = function() end }
    end
    local tracks = { Idle = track(), Walk = track(), Crouch = track(), Fall = track(), Jump = track() }
    local view = setmetatable({
        model = { state = 1, x = 0, y = 0, z = 0, rwalk = 1.04, rcrouch = -0.03, jumpSequence = 0 },
        airBlend = 0,
        jumpSequence = 0,
        jumpTime = 1,
        tracks = tracks,
        root = {},
    }, { __index = WalkerView })
    view:update(1 / 60)
    local inRange = true
    for _, item in pairs(tracks) do
        inRange = inRange and item.weight >= 0 and item.weight <= 1
    end
    self:check(inRange, 'animation weights stay within 0..1 for overshooting walk and crouch blends')
end

return Module
