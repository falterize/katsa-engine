local ipairs = require('../math.array').ipairs

local Voice = {}
Voice.__index = Voice

function Voice:pause()
    assert(not self.released, 'Cannot pause a released voice')
    self.manualPause = true
    for _, source in ipairs(self.sources) do
        source:pause()
    end
end

function Voice:resume()
    assert(not self.released, 'Cannot resume a released voice')
    self.manualPause = false
    self.timeWasPlaying = true
    self.mixer:apply(self)
    if not self.mixer.paused and not self.timePaused then
        for _, source in ipairs(self.sources) do
            source:play()
        end
    end
end

function Voice:stop()
    if self.released then
        return
    end
    self.stopped = true
    for _, source in ipairs(self.sources) do
        source:stop()
    end
end

function Voice:isPlaying()
    return not self.released and self.source:isPlaying()
end

function Voice:setVolume(volume)
    assert(
        type(volume) == 'number' and volume >= 0 and volume <= 1,
        'Voice volume must be between 0 and 1'
    )
    self.volume = volume
    self.mixer:apply(self)
    return self
end

function Voice:setPitch(pitch)
    assert(
        type(pitch) == 'number' and pitch > 0 and pitch <= 8,
        'Voice pitch must be between 0 and 8'
    )
    self.pitch = pitch
    self.mixer:apply(self)
    return self
end

function Voice:setLooping(loop)
    for _, source in ipairs(self.sources) do
        source:setLooping(loop)
    end
    return self
end

function Voice:release()
    if self.released then
        return
    end
    for _, source in ipairs(self.sources) do
        source:stop()
        source:release()
    end
    self.released = true
end

return Voice
