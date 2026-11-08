-- The microphone opens shortly after the session starts, not on the first Tab or talk press.
local Module = {}

function Module.run(self)
    local Voice = require('source.game.scenes.multiplayerCars.scripts.game.voice')
    local chain = {}
    chain.unreliable = function() return chain end
    chain.onClient = function() return chain end
    local client = { client = { remote = function() return chain end } }
    local opened = 0
    local real = katsa.audio.openCapture
    katsa.audio.openCapture = function()
        opened = opened + 1
        return nil, 'test'
    end
    local voice = Voice.new(client, {})
    voice:update(0.5)
    self:check(opened == 0, 'The microphone stays closed right after the session starts')
    voice:update(1.5)
    voice:update(0.1)
    katsa.audio.openCapture = real
    self:check(opened == 1, 'The microphone is opened once, by the update after the warm-up delay')
end

return Module
