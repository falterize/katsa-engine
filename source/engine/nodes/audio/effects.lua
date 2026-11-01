local pairs = require('source.engine.math.array').pairs
-- Only real LÖVE 11.x effect types are exposed. Pitch uses Source:setPitch.
local Node = require('source.engine.nodes.core.baseNode')
require('source.engine.nodes.audio.soundEffect')

local definitions = {
    SoundReverb = {
        effectType = 'reverb',
        gain = 0.35,
        decaytime = 1.8,
        density = 1,
        diffusion = 1,
    },
    SoundEcho = {
        effectType = 'echo',
        delay = 0.15,
        tapdelay = 0.1,
        damping = 0.5,
        feedback = 0.4,
        spread = -1,
    },
    SoundChorus = {
        effectType = 'chorus',
        waveform = 'sine',
        rate = 1.1,
        depth = 0.3,
        feedback = 0.2,
        delay = 0.016,
    },
    SoundDistortion = { effectType = 'distortion', gain = 0.1, edge = 0.2 },
    SoundPitch = { effectType = 'pitch', playbackSpeed = 1 },
    SoundFilter = { effectType = 'filter', filterType = 'lowpass', highgain = 0.15, lowgain = 1 },
}
for name, defaults in pairs(definitions) do
    local Class = Node.define(name, 'SoundEffect')
    local settings = defaults

    function Class.initialize(self)
        for key, value in pairs(settings) do
            if self[key] == nil then
                self[key] = value
            end
        end
    end
end

return definitions
