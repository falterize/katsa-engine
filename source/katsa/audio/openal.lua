-- OpenAL driver: turns Source state into OpenAL sources. Sound data is uploaded once per SoundData
-- and shared by every Source (and clone) that plays it.
local ffi = require('ffi')
local Native = require('source.katsa.core.native')

ffi.cdef([[
typedef struct ALCdevice ALCdevice;
typedef struct ALCcontext ALCcontext;
ALCdevice* alcOpenDevice(const char* name);
int alcCloseDevice(ALCdevice* device);
ALCcontext* alcCreateContext(ALCdevice* device, const int* attributes);
int alcMakeContextCurrent(ALCcontext* context);
void alcDestroyContext(ALCcontext* context);
void alGenSources(int count, unsigned int* sources);
void alDeleteSources(int count, const unsigned int* sources);
void alGenBuffers(int count, unsigned int* buffers);
void alDeleteBuffers(int count, const unsigned int* buffers);
void alBufferData(unsigned int buffer, int format, const void* data, int size, int frequency);
void alSourcei(unsigned int source, int parameter, int value);
void alSourcef(unsigned int source, int parameter, float value);
void alSource3f(unsigned int source, int parameter, float x, float y, float z);
void alSourcePlay(unsigned int source);
void alSourcePause(unsigned int source);
void alSourceStop(unsigned int source);
void alGetSourcei(unsigned int source, int parameter, int* value);
void alListenerf(int parameter, float value);
void alListener3f(int parameter, float x, float y, float z);
void alListenerfv(int parameter, const float* values);
void alDistanceModel(int model);
void alDopplerFactor(float value);
int alGetError(void);
]])

local AL = {
    SOURCE_RELATIVE = 0x202, CONE_INNER_ANGLE = 0x1001, CONE_OUTER_ANGLE = 0x1002, PITCH = 0x1003,
    POSITION = 0x1004, DIRECTION = 0x1005, VELOCITY = 0x1006, LOOPING = 0x1007, BUFFER = 0x1009,
    GAIN = 0x100A, MIN_GAIN = 0x100D, MAX_GAIN = 0x100E, ORIENTATION = 0x100F,
    SOURCE_STATE = 0x1010, PLAYING = 0x1012, REFERENCE_DISTANCE = 0x1020, ROLLOFF_FACTOR = 0x1021,
    CONE_OUTER_GAIN = 0x1022, MAX_DISTANCE = 0x1023, SEC_OFFSET = 0x1024,
    FORMAT_MONO16 = 0x1101, FORMAT_STEREO16 = 0x1103,
}

local distanceModels = {
    none = 0xD000, inverse = 0xD001, inverseclamped = 0xD002, linear = 0xD003,
    linearclamped = 0xD004, exponent = 0xD005, exponentclamped = 0xD006,
}

local Driver = { name = 'openal', effectsSupported = false, maxSourceEffects = 0 }

local al, device, context
local voices = setmetatable({}, { __mode = 'k' }) -- Source -> OpenAL source id
local buffers = setmetatable({}, { __mode = 'k' }) -- SoundData -> shared buffer holder

local function toDegrees(radians)
    return radians * 180 / math.pi
end

-- One AL buffer per SoundData, deleted when the data is collected and no source uses it.
local function bufferFor(data)
    local holder = buffers[data]
    if holder then
        return holder.id
    end
    local id = ffi.new('unsigned int[1]')
    al.alGenBuffers(1, id)
    local format = data:getChannelCount() == 1 and AL.FORMAT_MONO16 or AL.FORMAT_STEREO16
    al.alBufferData(id[0], format, data:getFFIPointer(), data:getSize(), data:getSampleRate())
    holder = { id = id[0] }
    holder.guard = ffi.gc(ffi.new('char[1]'), function()
        local ids = ffi.new('unsigned int[1]', holder.id)
        al.alDeleteBuffers(1, ids)
    end)
    buffers[data] = holder
    return holder.id
end

function Driver.createVoice(source)
    local id = ffi.new('unsigned int[1]')
    al.alGenSources(1, id)
    voices[source] = id[0]
    al.alSourcei(id[0], AL.BUFFER, bufferFor(source._data))
    Driver.update(source)
end

function Driver.destroyVoice(source)
    local id = voices[source]
    if id then
        voices[source] = nil
        al.alSourceStop(id)
        al.alSourcei(id, AL.BUFFER, 0)
        al.alDeleteSources(1, ffi.new('unsigned int[1]', id))
    end
end

function Driver.update(source)
    local id = voices[source]
    if not id then
        return
    end
    local p, v, d = source._position, source._velocity, source._direction
    al.alSourcef(id, AL.GAIN, source._volume)
    al.alSourcef(id, AL.PITCH, source._pitch)
    al.alSourcei(id, AL.LOOPING, source._looping and 1 or 0)
    al.alSource3f(id, AL.POSITION, p[1], p[2], p[3])
    al.alSource3f(id, AL.VELOCITY, v[1], v[2], v[3])
    al.alSource3f(id, AL.DIRECTION, d[1], d[2], d[3])
    al.alSourcef(id, AL.CONE_INNER_ANGLE, toDegrees(source._cone[1]))
    al.alSourcef(id, AL.CONE_OUTER_ANGLE, toDegrees(source._cone[2]))
    al.alSourcef(id, AL.CONE_OUTER_GAIN, source._cone[3])
    al.alSourcei(id, AL.SOURCE_RELATIVE, source._relative and 1 or 0)
    al.alSourcef(id, AL.ROLLOFF_FACTOR, source._rolloff)
    al.alSourcef(id, AL.REFERENCE_DISTANCE, source._refDistance)
    al.alSourcef(id, AL.MAX_DISTANCE, source._maxDistance)
    al.alSourcef(id, AL.MIN_GAIN, source._minVolume)
    al.alSourcef(id, AL.MAX_GAIN, source._maxVolume)
end

function Driver.seek(source, offset)
    local id = voices[source]
    if id then
        al.alSourcef(id, AL.SEC_OFFSET, offset)
    end
end

function Driver.play(source)
    local id = voices[source]
    if id then
        Driver.update(source)
        al.alSourcef(id, AL.SEC_OFFSET, source._startOffset or 0)
        al.alSourcePlay(id)
    end
end

function Driver.pause(source)
    local id = voices[source]
    if id then
        al.alSourcePause(id)
    end
end

function Driver.stop(source)
    local id = voices[source]
    if id then
        al.alSourceStop(id)
    end
end

-- True while OpenAL reports the voice of `source` as playing.
function Driver.isPlaying(source)
    local id = voices[source]
    if not id then
        return false
    end
    local state = ffi.new('int[1]')
    al.alGetSourcei(id, AL.SOURCE_STATE, state)
    return state[0] == AL.PLAYING
end

function Driver.updateListener(listener)
    local o = listener.orientation
    al.alListenerf(AL.GAIN, listener.volume)
    al.alListener3f(AL.POSITION, unpack(listener.position))
    al.alListener3f(AL.VELOCITY, unpack(listener.velocity))
    al.alListenerfv(AL.ORIENTATION, ffi.new('float[6]', o[1], o[2], o[3], o[4], o[5], o[6]))
end

-- Distance model and Doppler factor are global in OpenAL.
function Driver.updateGlobal(state)
    al.alDistanceModel(distanceModels[state.distanceModel or 'inverseclamped'])
    al.alDopplerFactor(state.doppler or 1)
end

function Driver.defineEffect() end
function Driver.removeEffect() end

-- Opens the default output device. Returns the driver, or nil plus the reason.
function Driver.open(deviceName)
    local lib, problem = Native.load('OpenAL')
    if not lib then
        return nil, problem
    end
    al = lib
    device = al.alcOpenDevice(deviceName)
    if device == nil then
        return nil, 'no audio output device'
    end
    context = al.alcCreateContext(device, nil)
    if context == nil or al.alcMakeContextCurrent(context) == 0 then
        al.alcCloseDevice(device)
        return nil, 'cannot create an OpenAL context'
    end
    return Driver
end

function Driver.close()
    if context then
        al.alcMakeContextCurrent(nil)
        al.alcDestroyContext(context)
        al.alcCloseDevice(device)
        context, device = nil, nil
    end
end

return Driver
