-- katsa.sound: SoundData and decoders (Ogg Vorbis via stb_vorbis, PCM/float WAV in Lua).
local ffi = require('ffi')
local nativeLib = require('source.katsa.core.nativeLib')

local Sound = {}
local SoundData = {}
SoundData.__index = SoundData

local function make(samples, rate, bits, channels, frames)
    local self = setmetatable({
        _buffer = samples, _rate = rate, _bits = bits, _channels = channels, _frames = frames,
    }, SoundData)
    self._size = frames * channels * 2
    return self
end

local function le16(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

local function le32(s,
    i) local a, b, c, d = s:byte(i, i + 3) return a + b * 256 + c * 65536 + d * 16777216 end

local function decodeWav(data)
    if data:sub(1, 4) ~= 'RIFF' or data:sub(9, 12) ~= 'WAVE' then
        return nil
    end
    local position, format, pcm = 13, nil, nil
    while position + 8 <= #data do
        local id, size = data:sub(position, position + 3), le32(data, position + 4)
        local body = position + 8
        if id == 'fmt ' then
            format = {
                tag = le16(data,
                    body), channels = le16(data, body + 2), rate = le32(data, body + 4),
                bits = le16(data, body + 14),
            }
            if format.tag == 0xFFFE and size >= 26 then
                format.tag = le16(data, body + 24)
            end
        elseif id == 'data' then
            pcm = { start = body, size = math.min(size, #data - body + 1) }
            break
        end
        position = body + size + (size % 2)
    end
    if not format or not pcm then
        return nil, 'Invalid WAV file'
    end
    local bytes = format.bits / 8
    local frames = math.floor(pcm.size / (bytes * format.channels))
    local count = frames * format.channels
    local out = ffi.new('int16_t[?]', math.max(count, 1))
    local start = pcm.start
    local function sampleAt(i)
        local at = start + i * bytes
        if format.tag == 3 then
            local raw = data:sub(at, at + bytes - 1)
            local value = ffi.new(bytes == 8 and 'double[1]' or 'float[1]')
            ffi.copy(value, raw, bytes)
            return math.max(-1, math.min(1, value[0])) * 32767
        elseif format.bits == 8 then
            return (data:byte(at) - 128) * 256
        elseif format.bits == 16 then
            local v = le16(data, at)
            return v >= 32768 and v - 65536 or v
        elseif format.bits == 24 then
            local v = data:byte(at + 1) + data:byte(at + 2) * 256 + data:byte(at + 3) * 65536
            if v >= 8388608 then
                v = v - 16777216
            end
            return v / 256
        elseif format.bits == 32 then
            local v = le32(data, at)
            if v >= 2147483648 then
                v = v - 4294967296
            end
            return v / 65536
        end
        error('Unsupported WAV bit depth: ' .. format.bits)
    end
    for i = 0, count - 1 do
        out[i] = sampleAt(i)
    end
    return make(out, format.rate, format.bits == 8 and 8 or 16, format.channels, frames)
end

local function decodeOgg(data)
    if data:sub(1, 4) ~= 'OggS' then
        return nil
    end
    local samples, channels, rate, frames = nativeLib.decodeVorbis(data)
    if not samples then
        return nil, 'Could not decode Ogg Vorbis data'
    end
    return make(samples, rate, 16, channels, frames)
end

local function sourceString(source)
    if type(source) == 'string' and #source < 1024 and not source:find('\0', 1, true) then
        local content = require('source.katsa.core.filesystem').read(source)
        if not content then
            error('Could not open file ' .. source .. '. Does not exist.', 3)
        end
        return content
    end
    return source:getString()
end

function Sound.newSoundData(a, b, c, d)
    if type(a) == 'number' then
        local frames, rate, bits, channels = a, b or 44100, c or 16, d or 1
        assert(bits == 8 or bits == 16, 'Invalid bit depth: ' .. tostring(bits))
        assert(channels == 1 or channels == 2, 'Invalid channel count: ' .. tostring(channels))
        assert(frames > 0, 'Invalid sample count')
        return make(ffi.new('int16_t[?]', frames * channels), rate, bits, channels, frames)
    end
    local data = sourceString(a)
    local decoded, message = decodeWav(data)
    if not decoded and not message then
        decoded, message = decodeOgg(data)
    end
    if not decoded then
        error(message or 'Could not decode sound data: only Ogg Vorbis and WAV are supported', 2)
    end
    return decoded
end

function SoundData:getSampleCount()
    return
    self._frames * self._channels
end

function SoundData:getSampleRate()
    return
    self._rate
end

function SoundData:getBitDepth()
    return
    self._bits
end

function SoundData:getChannelCount()
    return
    self._channels
end

function SoundData:getDuration()
    return
    self._frames / self._rate
end

function SoundData:getSize()
    return
    self._size
end

function SoundData:getPointer()
    return
    self._buffer
end

function SoundData:getFFIPointer()
    return
    self._buffer
end

function SoundData:getString()
    return
    ffi.string(self._buffer, self._size)
end

local function indexOf(self, i, channel)
    if channel then
        return i * self._channels + (channel - 1)
    end
    return i
end

function SoundData:getSample(i, channel)
    local index = indexOf(self, i, channel)
    assert(index >= 0 and index < self._frames * self._channels,
        'Attempt to get out-of-range sample!')
    return self._buffer[index] / 32768
end

function SoundData:setSample(i, a, b)
    local channel, value = nil, a
    if b ~= nil then
        channel, value = a, b
    end
    local index = indexOf(self, i, channel)
    assert(index >= 0 and index < self._frames * self._channels,
        'Attempt to set out-of-range sample!')
    self._buffer[index] = math.floor(math.max(-1, math.min(1, value)) * 32767 + 0.5)
end

function SoundData:clone()
    local copy = ffi.new('int16_t[?]', math.max(self._frames * self._channels, 1))
    ffi.copy(copy, self._buffer, self._size)
    return make(copy, self._rate, self._bits, self._channels, self._frames)
end

function SoundData:release()
    return true
end

function SoundData:type()
    return 'SoundData'
end

function SoundData:typeOf(name)
    return name == 'SoundData' or name == 'Data' or name == 'Object'
end

return Sound
