-- katsa.audio: sources, listener and effects. Playback state lives here; a driver (OpenAL, or the
-- silent
-- null driver used for servers and tests) turns it into sound.
local Sound = require('source.katsa.sound')
local timer = require('source.katsa.core.timer')

local Audio = {}
local Methods = {}
Methods.__index = Methods

local listener = {
    position = { 0, 0, 0 },
    orientation = { 0, 0, -1, 0, 1, 0 },
    velocity = { 0, 0, 0 },
    volume = 1,
}
local effects = {}
local driver = require('source.katsa.audio.nullDriver')
local sources = setmetatable({}, { __mode = 'k' })

function Audio.setDriver(newDriver)
    driver = newDriver
end

function Audio.getDriver()
    return driver
end

function Audio.newSource(a, kind)
    local data
    if type(a) == 'table' and a.getSampleCount then
        data = a
    else
        data = Sound.newSoundData(a)
    end
    local self = setmetatable({
        _data = data, _type = kind or 'stream', _looping = false, _volume = 1, _pitch = 1,
        _position = { 0, 0, 0 }, _velocity = { 0, 0, 0 }, _direction = { 0, 0, 0 },
        _cone = { 6.2831855, 6.2831855, 0 },
        _relative = false, _rolloff = 1, _refDistance = 1, _maxDistance = 3.4028235e38,
        _airAbsorption = 0,
        _minVolume = 0, _maxVolume = 1, _offset = 0, _state = 'stopped', _effects = {},
        _filter = nil,
    }, Methods)
    sources[self] = true
    driver.createVoice(self)
    return self
end

-- Position in seconds, advancing with the timer while playing.
local function currentOffset(self)
    if self._state ~= 'playing' then
        return self._offset
    end
    local duration = self._data:getDuration()
    local elapsed = (timer.getTime() - self._startedAt) * self._pitch + self._startOffset
    if elapsed >= duration then
        if self._looping and duration > 0 then
            return elapsed % duration
        end
        self._state, self._offset = 'stopped', 0
        driver.stop(self)
        return 0
    end
    return elapsed
end

function Methods:play()
    if self._state == 'playing' then
        return true
    end
    self._startOffset = self._state == 'paused' and self._offset or 0
    self._startedAt = timer.getTime()
    self._state = 'playing'
    driver.play(self)
    return true
end

function Methods:stop()
    self._state, self._offset = 'stopped', 0
    driver.stop(self)
end

function Methods:pause()
    if self._state == 'playing' then
        self._offset = currentOffset(self)
        if self._state == 'playing' then
            self._state = 'paused'
            driver.pause(self)
        end
    end
end

function Methods:resume()
    if self._state == 'paused' then
        self:play()
    end
end

function Methods:isPlaying()
    currentOffset(self)
    return self._state == 'playing'
end

function Methods:isPaused()
    return
    self._state == 'paused'
end

function Methods:isStopped()
    currentOffset(self)
    return self._state == 'stopped'
end

function Methods:rewind()
    self:seek(0)
end

function Methods:seek(offset, unit)
    if unit == 'samples' then
        offset = offset / self._data:getSampleRate()
    end
    self._offset = offset
    if self._state == 'playing' then
        self._startOffset, self._startedAt = offset, timer.getTime()
    end
    driver.seek(self, offset)
end

function Methods:tell(unit)
    local offset = currentOffset(self)
    if unit == 'samples' then
        return math.floor(offset * self._data:getSampleRate())
    end
    return offset
end

function Methods:getDuration(unit)
    if unit == 'samples' then
        return self._data:getSampleCount() / self._data:getChannelCount()
    end
    return self._data:getDuration()
end

function Methods:setLooping(value)
    self._looping = not not value
    driver.update(self)
end

function Methods:isLooping()
    return
    self._looping
end

function Methods:setVolume(value)
    self._volume = value
    driver.update(self)
end

function Methods:getVolume()
    return
    self._volume
end

function Methods:setPitch(value)
    if self._state == 'playing' then
        self._offset = currentOffset(self)
        self._startOffset, self._startedAt = self._offset, timer.getTime()
    end
    self._pitch = value
    driver.update(self)
end

function Methods:getPitch()
    return
    self._pitch
end

function Methods:setPosition(x, y, z)
    self._position = { x, y, z or 0 }
    driver.update(self)
end

function Methods:getPosition()
    return
    unpack(self._position)
end

function Methods:setVelocity(x, y, z)
    self._velocity = { x, y, z or 0 }
    driver.update(self)
end

function Methods:getVelocity()
    return
    unpack(self._velocity)
end

function Methods:setDirection(x, y, z)
    self._direction = { x, y, z or 0 }
    driver.update(self)
end

function Methods:getDirection()
    return
    unpack(self._direction)
end

function Methods:setCone(inner, outer,
    gain) self._cone = { inner, outer, gain or 0 } driver.update(self) end
function Methods:getCone()
    return
    unpack(self._cone)
end

function Methods:setRelative(value)
    self._relative = not not value
    driver.update(self)
end

function Methods:isRelative()
    return
    self._relative
end

function Methods:setRolloff(value)
    self._rolloff = value
    driver.update(self)
end

function Methods:getRolloff()
    return
    self._rolloff
end

function Methods:setAttenuationDistances(ref, max)
    self._refDistance, self._maxDistance = ref, max
    driver.update(self)
end

function Methods:getAttenuationDistances()
    return
    self._refDistance, self._maxDistance
end

function Methods:setAirAbsorption(value)
    self._airAbsorption = value
    driver.update(self)
end

function Methods:getAirAbsorption()
    return
    self._airAbsorption
end

function Methods:setVolumeLimits(min,
    max) self._minVolume, self._maxVolume = min, max driver.update(self) end
function Methods:getVolumeLimits()
    return
    self._minVolume, self._maxVolume
end

function Methods:getChannelCount()
    return
    self._data:getChannelCount()
end

function Methods:getType()
    return
    self._type
end

function Methods:setFilter(settings)
    self._filter = settings
    driver.update(self)
    return true
end

function Methods:getFilter()
    return
    self._filter
end

function Methods:setEffect(name, filter)
    if filter == false then
        self._effects[name] = nil
        driver.update(self)
        return true
    end
    if not effects[name] then
        error(('Effect %s has not been defined.'):format(tostring(name)), 2)
    end
    self._effects[name] = filter or true
    driver.update(self)
    return true
end

function Methods:getEffect(name)
    return
    self._effects[name]
end

function Methods:getActiveEffects()
    local list = {}
    for name in pairs(self._effects) do
        list[#list + 1] = name
    end
    table.sort(list)
    return list
end

function Methods:clone()
    local copy = Audio.newSource(self._data, self._type)
    copy._looping, copy._volume, copy._pitch = self._looping, self._volume, self._pitch
    copy._position = { unpack(self._position) }
    copy._velocity = { unpack(self._velocity) }
    copy._direction = { unpack(self._direction) }
    copy._cone = { unpack(self._cone) }
    copy._relative = self._relative
    copy._rolloff = self._rolloff
    copy._refDistance, copy._maxDistance = self._refDistance, self._maxDistance
    for name, value in pairs(self._effects) do
        copy._effects[name] = value
    end
    driver.update(copy)
    return copy
end

function Methods:release()
    driver.destroyVoice(self)
    self._state = 'stopped'
    return true
end

function Methods:type()
    return 'Source'
end

function Methods:typeOf(name)
    return name == 'Source' or name == 'Object'
end

-- Listener -------------------------------------------------------------------------------------

function Audio.setPosition(x, y,
    z) listener.position = { x, y, z } driver.updateListener(listener) end
function Audio.getPosition()
    return
    unpack(listener.position)
end

function Audio.setOrientation(fx, fy, fz, ux, uy,
    uz) listener.orientation = { fx, fy, fz, ux, uy, uz } driver.updateListener(listener) end
function Audio.getOrientation()
    return
    unpack(listener.orientation)
end

function Audio.setVelocity(x, y,
    z) listener.velocity = { x, y, z } driver.updateListener(listener) end
function Audio.getVelocity()
    return
    unpack(listener.velocity)
end

function Audio.setVolume(value)
    listener.volume = value
    driver.updateListener(listener)
end

function Audio.getVolume()
    return listener.volume
end

local function each(list, fn)
    for source in pairs(sources) do
        if not list or list[source] then
            fn(source)
        end
    end
end

function Audio.play(...)
    for _, source in ipairs({ ... }) do
        if type(source) == 'table' and source.play then
            source:play()
        else
            for _, s in ipairs(source) do s:play() end
        end
    end
end

function Audio.stop(...)
    if select('#', ...) == 0 then
        each(nil, function(s) s:stop() end)
        return
    end
    for _, source in ipairs({ ... }) do
        if source.stop then source:stop() else for _, s in ipairs(source) do s:stop() end end
    end
end

function Audio.pause(...)
    if select('#', ...) == 0 then
        local paused = {}
        each(nil,
            function(s) if s._state == 'playing' then s:pause() paused[#paused + 1] = s end end)
        return paused
    end
    for _, source in ipairs({ ... }) do source:pause() end
end

function Audio.getActiveSourceCount()
    local count = 0
    each(nil, function(s) if s:isPlaying() then count = count + 1 end end)
    return count
end

-- Effects ----------------------------------------------------------------------------------------

function Audio.isEffectsSupported()
    return driver.effectsSupported and true or false
end

function Audio.getMaxSourceEffects()
    return driver.maxSourceEffects or 0
end

function Audio.setEffect(name, settings)
    if settings == false then
        effects[name] = nil
        driver.removeEffect(name)
        return true
    end
    assert(type(settings) == 'table', 'Effect settings must be a table')
    effects[name] = settings
    driver.defineEffect(name, settings)
    return true
end

function Audio.getEffect(name)
    return effects[name]
end

function Audio.getActiveEffects()
    local list = {}
    for name in pairs(effects) do list[#list + 1] = name end
    table.sort(list)
    return list
end

function Audio.getDistanceModel()
    return Audio._distanceModel or 'inverseclamped'
end

function Audio.setDistanceModel(model)
    Audio._distanceModel = model
end

function Audio.getDopplerScale()
    return Audio._doppler or 1
end

function Audio.setDopplerScale(value)
    Audio._doppler = value
end

function Audio.getSourceCount()
    return
    Audio.getActiveSourceCount()
end

return Audio
