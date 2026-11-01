-- Source objects: playback state, spatial properties and per-source effects.

local Sound = require('source.katsa.sound')
local timer = require('source.katsa.core.timer')
local State = require('source.katsa.audio.state')
local Audio = State.Audio
local Methods = State.Methods

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
    State.sources[self] = true
    State.driver.createVoice(self)
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
        State.driver.stop(self)
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
    State.driver.play(self)
    return true
end

function Methods:stop()
    self._state, self._offset = 'stopped', 0
    State.driver.stop(self)
end

function Methods:pause()
    if self._state == 'playing' then
        self._offset = currentOffset(self)
        if self._state == 'playing' then
            self._state = 'paused'
            State.driver.pause(self)
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
    return self._state == 'paused'
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
    State.driver.seek(self, offset)
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
    State.driver.update(self)
end

function Methods:isLooping()
    return self._looping
end

function Methods:setVolume(value)
    self._volume = value
    State.driver.update(self)
end

function Methods:getVolume()
    return self._volume
end

function Methods:setPitch(value)
    if self._state == 'playing' then
        self._offset = currentOffset(self)
        self._startOffset, self._startedAt = self._offset, timer.getTime()
    end
    self._pitch = value
    State.driver.update(self)
end

function Methods:getPitch()
    return self._pitch
end

function Methods:setPosition(x, y, z)
    self._position = { x, y, z or 0 }
    State.driver.update(self)
end

function Methods:getPosition()
    return unpack(self._position)
end

function Methods:setVelocity(x, y, z)
    self._velocity = { x, y, z or 0 }
    State.driver.update(self)
end

function Methods:getVelocity()
    return unpack(self._velocity)
end

function Methods:setDirection(x, y, z)
    self._direction = { x, y, z or 0 }
    State.driver.update(self)
end

function Methods:getDirection()
    return unpack(self._direction)
end

function Methods:setCone(inner, outer, gain)
    self._cone = { inner, outer, gain or 0 }
    State.driver.update(self)
end

function Methods:getCone()
    return unpack(self._cone)
end

function Methods:setRelative(value)
    self._relative = not not value
    State.driver.update(self)
end

function Methods:isRelative()
    return self._relative
end

function Methods:setRolloff(value)
    self._rolloff = value
    State.driver.update(self)
end

function Methods:getRolloff()
    return self._rolloff
end

function Methods:setAttenuationDistances(ref, max)
    self._refDistance, self._maxDistance = ref, max
    State.driver.update(self)
end

function Methods:getAttenuationDistances()
    return self._refDistance, self._maxDistance
end

function Methods:setAirAbsorption(value)
    self._airAbsorption = value
    State.driver.update(self)
end

function Methods:getAirAbsorption()
    return self._airAbsorption
end

function Methods:setVolumeLimits(min, max)
    self._minVolume = min
    self._maxVolume = max
    State.driver.update(self)
end

function Methods:getVolumeLimits()
    return self._minVolume, self._maxVolume
end

function Methods:getChannelCount()
    return self._data:getChannelCount()
end

function Methods:getType()
    return self._type
end

function Methods:setFilter(settings)
    self._filter = settings
    State.driver.update(self)
    return true
end

function Methods:getFilter()
    return self._filter
end

function Methods:setEffect(name, filter)
    if filter == false then
        self._effects[name] = nil
        State.driver.update(self)
        return true
    end
    if not State.effects[name] then
        error(('Effect %s has not been defined.'):format(tostring(name)), 2)
    end
    self._effects[name] = filter or true
    State.driver.update(self)
    return true
end

function Methods:getEffect(name)
    return self._effects[name]
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
    State.driver.update(copy)
    return copy
end

function Methods:release()
    State.driver.destroyVoice(self)
    self._state = 'stopped'
    return true
end

function Methods:type()
    return 'Source'
end

function Methods:typeOf(name)
    return name == 'Source' or name == 'Object'
end
